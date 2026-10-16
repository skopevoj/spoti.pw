#import "Core/SGCore.h"
#import "Core/SGRebind.h"
#import "SGConnectDNS.h"
#import <errno.h>
#import <arpa/inet.h>
#import <netinet/in.h>
#import <QuartzCore/QuartzCore.h>
#import <fcntl.h>
#import <poll.h>
#import <stdatomic.h>
#import <string.h>
#import <sys/socket.h>
#import <sys/uio.h>
#import <unistd.h>

static ssize_t (*sg_originalSendTo)(int, const void *, size_t, int, const struct sockaddr *, socklen_t);
static ssize_t (*sg_originalSendMsg)(int, const struct msghdr *, int);
static ssize_t (*sg_originalRecvFrom)(int, void *, size_t, int, struct sockaddr *, socklen_t *);
static ssize_t (*sg_originalRecvMsg)(int, struct msghdr *, int);
static NSObject *sg_discoveryLock;
static NSMutableArray<NSDictionary *> *sg_bonjourTargets;
static NSMutableArray<NSDictionary *> *sg_injectedPackets;
static atomic_uint_fast64_t sg_injectedExpiryMs;
@class SGBridgeRound;
static NSMutableArray<SGBridgeRound *> *sg_rounds;
static dispatch_queue_t sg_bridgeQueue;

@interface SGBridgeRound : NSObject
@property (nonatomic) int originalFD;
@property (nonatomic) int retainedFD;
@property (nonatomic, strong) NSData *query;
@end
@implementation SGBridgeRound
@end

@interface SGConnectTargetBrowser : NSObject <NSNetServiceBrowserDelegate, NSNetServiceDelegate>
@property (nonatomic, strong) NSNetServiceBrowser *browser;
@property (nonatomic, strong) NSMutableArray<NSNetService *> *services;
@property (nonatomic, strong) NSMutableSet<NSNetService *> *resolving;
@property (nonatomic, strong) NSMutableSet<NSNetService *> *retryScheduled;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *retryAttempts;
- (void)start;
@end

static SGConnectTargetBrowser *sg_targetBrowser;

static NSString *serviceKey(NSNetService *service) {
    return [NSString stringWithFormat:@"%@|%@|%@", service.name, service.type, service.domain];
}

static uint_fast64_t nowMilliseconds(void) { return (uint_fast64_t)(CACurrentMediaTime() * 1000.0); }

static void pruneInjectedPacketsLocked(CFTimeInterval now) {
    NSIndexSet *expired = [sg_injectedPackets indexesOfObjectsPassingTest:^BOOL(NSDictionary *entry, NSUInteger idx, BOOL *stop) {
        return now - [entry[@"time"] doubleValue] > 15.0;
    }];
    [sg_injectedPackets removeObjectsAtIndexes:expired];
    if (!sg_injectedPackets.count) atomic_store(&sg_injectedExpiryMs, 0);
}

// Called while sg_discoveryLock is held and before the send, so the receive hook's lock-free
// expiry check already sees it when the reply lands.
static NSDictionary *rememberInjectedPacketLocked(int fd, const void *bytes, size_t length,
                                                  const struct sockaddr *source, socklen_t sourceLength) {
    NSDictionary *packet = @{
        @"bytes": [NSData dataWithBytes:bytes length:length],
        @"fd": @(fd),
        @"source": [NSData dataWithBytes:source length:sourceLength],
        @"time": @(CACurrentMediaTime())
    };
    pruneInjectedPacketsLocked(CACurrentMediaTime());
    if (sg_injectedPackets.count == 64) [sg_injectedPackets removeObjectAtIndex:0];
    [sg_injectedPackets addObject:packet];
    atomic_store(&sg_injectedExpiryMs, nowMilliseconds() + 15000);
    return packet;
}

static BOOL isLoopbackSource(const struct sockaddr *source, socklen_t length) {
    if (!source) return NO;
    if (source->sa_family == AF_INET && length >= sizeof(struct sockaddr_in))
        return ntohl(((const struct sockaddr_in *)source)->sin_addr.s_addr) == INADDR_LOOPBACK;
    if (source->sa_family == AF_INET6 && length >= sizeof(struct sockaddr_in6))
        return IN6_IS_ADDR_LOOPBACK(&((const struct sockaddr_in6 *)source)->sin6_addr);
    return NO;
}

static BOOL mayHaveInjectedPackets(void) {
    uint_fast64_t expiry = atomic_load(&sg_injectedExpiryMs);
    if (!expiry) return NO;
    if (nowMilliseconds() <= expiry) return YES;
    atomic_compare_exchange_strong(&sg_injectedExpiryMs, &expiry, 0);
    return nowMilliseconds() <= atomic_load(&sg_injectedExpiryMs);
}

static void matchInjectedPacket(int fd, const void *bytes, size_t length, int flags,
                                struct sockaddr *source, socklen_t *sourceLength) {
    if (!mayHaveInjectedPackets() || !bytes || length < 12 || !source || !sourceLength ||
        !isLoopbackSource(source, *sourceLength)) return;
    @synchronized (sg_discoveryLock) {
        pruneInjectedPacketsLocked(CACurrentMediaTime());
        for (NSInteger i = (NSInteger)sg_injectedPackets.count - 1; i >= 0; i--) {
            NSDictionary *entry = sg_injectedPackets[(NSUInteger)i];
            if ([entry[@"fd"] intValue] != fd) continue;
            NSData *expected = entry[@"bytes"];
            if (length != expected.length || memcmp(expected.bytes, bytes, length) != 0) continue;

            NSData *realSource = entry[@"source"];
            const struct sockaddr *real = realSource.bytes;
            if (real->sa_family == source->sa_family && *sourceLength >= realSource.length) {
                memcpy(source, real, realSource.length);
                *sourceLength = (socklen_t)realSource.length;
            } else if (real->sa_family == AF_INET && source->sa_family == AF_INET6 &&
                       *sourceLength >= sizeof(struct sockaddr_in6)) {
                const struct sockaddr_in *ipv4 = (const struct sockaddr_in *)real;
                struct sockaddr_in6 mapped = {0};
                mapped.sin6_len = sizeof(mapped);
                mapped.sin6_family = AF_INET6;
                mapped.sin6_port = ipv4->sin_port;
                mapped.sin6_addr.s6_addr[10] = 0xff;
                mapped.sin6_addr.s6_addr[11] = 0xff;
                memcpy(&mapped.sin6_addr.s6_addr[12], &ipv4->sin_addr, sizeof(ipv4->sin_addr));
                memcpy(source, &mapped, sizeof(mapped));
                *sourceLength = sizeof(mapped);
            } else return;
            if (!(flags & MSG_PEEK)) [sg_injectedPackets removeObjectAtIndex:(NSUInteger)i];
            if (!sg_injectedPackets.count) atomic_store(&sg_injectedExpiryMs, 0);
            return;
        }
    }
}

static BOOL isMulticastDNS(const struct sockaddr *address, socklen_t length) {
    if (!address) return NO;
    if (address->sa_family == AF_INET && length >= sizeof(struct sockaddr_in)) {
        const struct sockaddr_in *ipv4 = (const struct sockaddr_in *)address;
        return ipv4->sin_port == htons(5353) && ipv4->sin_addr.s_addr == htonl(0xe00000fb);
    }
    if (address->sa_family == AF_INET6 && length >= sizeof(struct sockaddr_in6)) {
        static const unsigned char mdns6[16] = {0xff, 0x02, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xfb};
        const struct sockaddr_in6 *ipv6 = (const struct sockaddr_in6 *)address;
        return ipv6->sin6_port == htons(5353) && memcmp(&ipv6->sin6_addr, mdns6, sizeof(mdns6)) == 0;
    }
    return NO;
}

@implementation SGConnectTargetBrowser

- (void)start {
    self.services = [NSMutableArray array];
    self.resolving = [NSMutableSet set];
    self.retryScheduled = [NSMutableSet set];
    self.retryAttempts = [NSMutableDictionary dictionary];
    self.browser = [NSNetServiceBrowser new];
    self.browser.delegate = self;
    [self.browser searchForServicesOfType:@"_spotify-connect._tcp." inDomain:@"local."];
}

- (void)retryResolve:(NSNetService *)service {
    if (![self.services containsObject:service] || [self.retryScheduled containsObject:service]) return;
    NSString *key = serviceKey(service);
    NSUInteger attempt = [self.retryAttempts[key] unsignedIntegerValue];
    self.retryAttempts[key] = @(MIN(attempt + 1, 4));
    NSUInteger delay = MIN((NSUInteger)3 << MIN(attempt, 4), (NSUInteger)30);
    [self.retryScheduled addObject:service];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.retryScheduled removeObject:service];
        if (!self.retryAttempts[key] || ![self.services containsObject:service] ||
            [self.resolving containsObject:service]) return;
        [self.resolving addObject:service];
        [service resolveWithTimeout:5.0];
    });
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didFindService:(NSNetService *)service moreComing:(BOOL)moreComing {
    if ([self.services containsObject:service]) return;
    [self.resolving addObject:service];
    service.delegate = self;
    [self.services addObject:service];
    [service resolveWithTimeout:5.0];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didRemoveService:(NSNetService *)service moreComing:(BOOL)moreComing {
    [self.resolving removeObject:service];
    [self.retryScheduled removeObject:service];
    [self.retryAttempts removeObjectForKey:serviceKey(service)];
    [self.services removeObject:service];
    NSString *key = serviceKey(service);
    @synchronized (sg_discoveryLock) {
        NSIndexSet *matches = [sg_bonjourTargets indexesOfObjectsPassingTest:^BOOL(NSDictionary *target, NSUInteger idx, BOOL *stop) {
            return [target[@"key"] isEqualToString:key];
        }];
        [sg_bonjourTargets removeObjectsAtIndexes:matches];
    }
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didNotSearch:(NSDictionary<NSString *,NSNumber *> *)errorDict {
    SGLog(@"Connect discovery: Bonjour search failed (%@)", errorDict);
    [browser stop];
    @synchronized (sg_discoveryLock) { [sg_bonjourTargets removeAllObjects]; }
    [self.services removeAllObjects];
    [self.resolving removeAllObjects];
    [self.retryScheduled removeAllObjects];
    [self.retryAttempts removeAllObjects];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.browser != browser) return;
        self.browser = [NSNetServiceBrowser new];
        self.browser.delegate = self;
        [self.browser searchForServicesOfType:@"_spotify-connect._tcp." inDomain:@"local."];
    });
}

- (void)netServiceDidResolveAddress:(NSNetService *)service {
    [self.resolving removeObject:service];
    if (![self.services containsObject:service]) return;
    NSMutableArray<NSDictionary *> *resolved = [NSMutableArray array];
    NSString *key = serviceKey(service);
    for (NSData *data in service.addresses) {
        if (data.length < sizeof(struct sockaddr)) continue;
        const struct sockaddr *address = data.bytes;
        if (address->sa_family == AF_INET && data.length >= sizeof(struct sockaddr_in)) {
            struct sockaddr_in target = *(const struct sockaddr_in *)address;
            uint32_t ip = ntohl(target.sin_addr.s_addr);
            if (!ip || (ip >> 24) == 127 || (ip >> 28) == 14) continue;
            target.sin_port = htons(5353);
            [resolved addObject:@{ @"key": key, @"name": service.name,
                                   @"address": [NSData dataWithBytes:&target length:sizeof(target)] }];
        } else if (address->sa_family == AF_INET6 && data.length >= sizeof(struct sockaddr_in6)) {
            struct sockaddr_in6 target = *(const struct sockaddr_in6 *)address;
            if (IN6_IS_ADDR_UNSPECIFIED(&target.sin6_addr) || IN6_IS_ADDR_LOOPBACK(&target.sin6_addr) ||
                IN6_IS_ADDR_MULTICAST(&target.sin6_addr)) continue;
            target.sin6_port = htons(5353);
            [resolved addObject:@{ @"key": key, @"name": service.name,
                                   @"address": [NSData dataWithBytes:&target length:sizeof(target)] }];
        }
    }
    @synchronized (sg_discoveryLock) {
        NSIndexSet *matches = [sg_bonjourTargets indexesOfObjectsPassingTest:^BOOL(NSDictionary *target, NSUInteger idx, BOOL *stop) {
            return [target[@"key"] isEqualToString:key];
        }];
        [sg_bonjourTargets removeObjectsAtIndexes:matches];
        [sg_bonjourTargets addObjectsFromArray:resolved];
    }
    if (resolved.count) {
        [self.retryAttempts removeObjectForKey:serviceKey(service)];
        SGLog(@"Connect discovery: resolved %@ to %lu address(es)", service.name, (unsigned long)resolved.count);
    }
    else [self retryResolve:service];
}

- (void)netService:(NSNetService *)service didNotResolve:(NSDictionary<NSString *,NSNumber *> *)errorDict {
    [self.resolving removeObject:service];
    SGLog(@"Connect unicast bridge: could not resolve %@ (%@)", service.name, errorDict);
    [self retryResolve:service];
}

@end

static BOOL bridgeableError(int error) {
    return error == EACCES || error == EPERM || error == ENETUNREACH ||
           error == EHOSTUNREACH || error == EADDRNOTAVAIL;
}

static BOOL sameHost(const struct sockaddr *source, const struct sockaddr *target) {
    if (source->sa_family != target->sa_family) return NO;
    if (source->sa_family == AF_INET)
        return ((const struct sockaddr_in *)source)->sin_port == htons(5353) &&
            ((const struct sockaddr_in *)source)->sin_addr.s_addr == ((const struct sockaddr_in *)target)->sin_addr.s_addr;
    if (source->sa_family == AF_INET6)
        return ((const struct sockaddr_in6 *)source)->sin6_port == htons(5353) &&
            memcmp(&((const struct sockaddr_in6 *)source)->sin6_addr,
                   &((const struct sockaddr_in6 *)target)->sin6_addr, sizeof(struct in6_addr)) == 0;
    return NO;
}

static int newProbeSocket(int family) {
    int fd = socket(family, SOCK_DGRAM, IPPROTO_UDP);
    if (fd >= 0) {
        int flags = fcntl(fd, F_GETFL);
        if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0) { close(fd); return -1; }
    }
    return fd;
}

static void injectResponse(SGBridgeRound *round, const void *bytes, size_t length,
                           const struct sockaddr *source, socklen_t sourceLength, NSString *name) {
    struct sockaddr_storage local = {0};
    socklen_t localLength = sizeof(local);
    if (getsockname(round.retainedFD, (struct sockaddr *)&local, &localLength) != 0) return;
    struct sockaddr_storage loopback = {0};
    socklen_t loopbackLength;
    if (local.ss_family == AF_INET6) {
        struct sockaddr_in6 *address = (struct sockaddr_in6 *)&loopback;
        address->sin6_len = sizeof(*address);
        address->sin6_family = AF_INET6;
        address->sin6_port = ((struct sockaddr_in6 *)&local)->sin6_port;
        address->sin6_addr = in6addr_loopback;
        loopbackLength = sizeof(*address);
    } else if (local.ss_family == AF_INET && source->sa_family == AF_INET) {
        struct sockaddr_in *address = (struct sockaddr_in *)&loopback;
        address->sin_len = sizeof(*address);
        address->sin_family = AF_INET;
        address->sin_port = ((struct sockaddr_in *)&local)->sin_port;
        address->sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        loopbackLength = sizeof(*address);
    } else return;
    @synchronized (sg_discoveryLock) {
        NSDictionary *packet = rememberInjectedPacketLocked(round.originalFD, bytes, length, source, sourceLength);
        ssize_t sent = sendto(round.retainedFD, bytes, length, 0, (struct sockaddr *)&loopback, loopbackLength);
        if (sent != (ssize_t)length) {
            [sg_injectedPackets removeObjectIdenticalTo:packet];
            if (!sg_injectedPackets.count) atomic_store(&sg_injectedExpiryMs, 0);
            return;
        }
    }
    SGLog(@"Connect discovery: sent %lu-byte loopback response from %@", (unsigned long)length, name);
}

// Each round fans out through one nonblocking socket per family and collects replies in parallel.
// It also watches for targets that finish Bonjour resolution shortly after the failed send.
static void runBridgeRound(SGBridgeRound *round) {
    int ipv4FD = -1, ipv6FD = -1;
    NSMutableSet<NSData *> *attemptedTargets = [NSMutableSet set];
    NSMutableArray<NSDictionary *> *probed = [NSMutableArray array];
    CFTimeInterval started = CACurrentMediaTime(), lastSend = 0;
    NSUInteger replies = 0;
    while (replies < 32) {
        CFTimeInterval now = CACurrentMediaTime();
        if (now - started >= 1.2 || (!lastSend && now - started >= 0.7) ||
            (lastSend && now - started >= 0.7 && now - lastSend >= 0.45)) break;
        NSArray<NSDictionary *> *targets;
        @synchronized (sg_discoveryLock) { targets = [sg_bonjourTargets copy]; }
        for (NSDictionary *entry in targets) {
            if (attemptedTargets.count >= 64) break;
            NSData *addressData = entry[@"address"];
            if ([attemptedTargets containsObject:addressData]) continue;
            [attemptedTargets addObject:addressData];
            const struct sockaddr *address = addressData.bytes;
            int *probeFD = address->sa_family == AF_INET ? &ipv4FD : &ipv6FD;
            if (*probeFD < 0) *probeFD = newProbeSocket(address->sa_family);
            if (*probeFD < 0) continue;
            ssize_t sent = sendto(*probeFD, round.query.bytes, round.query.length, 0, address, (socklen_t)addressData.length);
            if (sent != (ssize_t)round.query.length) continue;
            [probed addObject:entry];
            lastSend = CACurrentMediaTime();
        }
        struct pollfd fds[2];
        nfds_t count = 0;
        if (ipv4FD >= 0) fds[count++] = (struct pollfd){ .fd = ipv4FD, .events = POLLIN };
        if (ipv6FD >= 0) fds[count++] = (struct pollfd){ .fd = ipv6FD, .events = POLLIN };
        int ready = count ? poll(fds, count, 40) : 0;
        if (!count) usleep(40000);
        if (ready <= 0) continue;
        for (nfds_t i = 0; i < count; i++) {
            if (!(fds[i].revents & POLLIN)) continue;
            for (unsigned drained = 0; drained < 8 && replies < 32; drained++) {
                unsigned char response[9000];
                struct sockaddr_storage source = {0};
                struct iovec payload = { .iov_base = response, .iov_len = sizeof(response) };
                struct msghdr message = {0};
                message.msg_name = &source;
                message.msg_namelen = sizeof(source);
                message.msg_iov = &payload;
                message.msg_iovlen = 1;
                ssize_t received = recvmsg(fds[i].fd, &message, MSG_DONTWAIT);
                if (received < 0) break;
                replies++;
                if (received < 12 || (message.msg_flags & MSG_TRUNC) ||
                    message.msg_namelen < sizeof(struct sockaddr) ||
                    (source.ss_family == AF_INET && message.msg_namelen < sizeof(struct sockaddr_in)) ||
                    (source.ss_family == AF_INET6 && message.msg_namelen < sizeof(struct sockaddr_in6)) ||
                    !SGDNSIsConnectResponse(response, (size_t)received, round.query.bytes, round.query.length)) continue;
                for (NSDictionary *entry in probed) {
                    NSData *addressData = entry[@"address"];
                    if (!sameHost((struct sockaddr *)&source, addressData.bytes)) continue;
                    injectResponse(round, response, (size_t)received, (struct sockaddr *)&source,
                                   message.msg_namelen, entry[@"name"]);
                    break;
                }
            }
        }
    }
    if (ipv4FD >= 0) close(ipv4FD);
    if (ipv6FD >= 0) close(ipv6FD);
    close(round.retainedFD);
    @synchronized (sg_discoveryLock) { [sg_rounds removeObject:round]; }
}

static BOOL bridgeFailedQuery(int fd, NSData *query) {
    if (!SGDNSIsConnectQuery(query.bytes, query.length)) return NO;
    struct sockaddr_storage peer = {0};
    socklen_t peerLength = sizeof(peer);
    if (getpeername(fd, (struct sockaddr *)&peer, &peerLength) == 0) return NO;
    int socketType = 0;
    socklen_t typeLength = sizeof(socketType);
    if (getsockopt(fd, SOL_SOCKET, SO_TYPE, &socketType, &typeLength) != 0 || socketType != SOCK_DGRAM) return NO;
    struct sockaddr_storage local = {0};
    socklen_t localLength = sizeof(local);
    if (getsockname(fd, (struct sockaddr *)&local, &localLength) != 0) return NO;
    if (local.ss_family == AF_INET && !((struct sockaddr_in *)&local)->sin_port) return NO;
    if (local.ss_family == AF_INET6 && !((struct sockaddr_in6 *)&local)->sin6_port) return NO;
    if (local.ss_family != AF_INET && local.ss_family != AF_INET6) return NO;
    SGBridgeRound *round;
    @synchronized (sg_discoveryLock) {
        for (SGBridgeRound *active in sg_rounds)
            if (active.originalFD == fd && [active.query isEqualToData:query]) return YES;
        if (sg_rounds.count >= 4) return NO;
        int retainedFD = dup(fd);
        if (retainedFD < 0) return NO;
        round = [SGBridgeRound new];
        round.originalFD = fd;
        round.retainedFD = retainedFD;
        round.query = query;
        [sg_rounds addObject:round];
    }
    dispatch_async(sg_bridgeQueue, ^{ runBridgeRound(round); });
    return YES;
}

static ssize_t bridgeSendTo(int fd, const void *bytes, size_t length, int flags,
                           const struct sockaddr *address, socklen_t addressLength) {
    ssize_t result = sg_originalSendTo(fd, bytes, length, flags, address, addressLength);
    int savedError = errno;
    if (result < 0 && bridgeableError(savedError) && isMulticastDNS(address, addressLength) &&
        bytes && length >= 12 && length <= 9000 &&
        bridgeFailedQuery(fd, [NSData dataWithBytes:bytes length:length])) {
        errno = savedError;
        return (ssize_t)length;
    }
    errno = savedError;
    return result;
}

static ssize_t bridgeSendMsg(int fd, const struct msghdr *message, int flags) {
    ssize_t result = sg_originalSendMsg(fd, message, flags);
    int savedError = errno;
    if (result < 0 && bridgeableError(savedError) && message && message->msg_iov &&
        message->msg_iovlen > 0 && message->msg_iovlen <= 32 &&
        isMulticastDNS(message->msg_name, message->msg_namelen)) {
        size_t total = 0;
        for (size_t i = 0; i < message->msg_iovlen; i++) {
            if (!message->msg_iov[i].iov_base || message->msg_iov[i].iov_len > 9000 - total) {
                total = 9001;
                break;
            }
            total += message->msg_iov[i].iov_len;
        }
        if (total >= 12 && total <= 9000) {
            NSMutableData *query = [NSMutableData dataWithCapacity:total];
            for (size_t i = 0; i < message->msg_iovlen; i++)
                [query appendBytes:message->msg_iov[i].iov_base length:message->msg_iov[i].iov_len];
            if (bridgeFailedQuery(fd, query)) {
                errno = savedError;
                return (ssize_t)query.length;
            }
        }
    }
    errno = savedError;
    return result;
}

static ssize_t bridgeRecvFrom(int fd, void *bytes, size_t length, int flags,
                             struct sockaddr *source, socklen_t *sourceLength) {
    ssize_t result = sg_originalRecvFrom(fd, bytes, length, flags, source, sourceLength);
    if (result >= 12 && result <= 9000 && (size_t)result <= length)
        matchInjectedPacket(fd, bytes, (size_t)result, flags, source, sourceLength);
    return result;
}

static ssize_t bridgeRecvMsg(int fd, struct msghdr *message, int flags) {
    ssize_t result = sg_originalRecvMsg(fd, message, flags);
    if (result < 12 || result > 9000 || !message || !message->msg_name ||
        !message->msg_iov || (message->msg_flags & MSG_TRUNC) || !mayHaveInjectedPackets()) return result;
    NSMutableData *bytes = [NSMutableData dataWithLength:(NSUInteger)result];
    size_t copied = 0;
    for (size_t i = 0; i < message->msg_iovlen && copied < (size_t)result; i++) {
        size_t part = MIN(message->msg_iov[i].iov_len, (size_t)result - copied);
        memcpy((char *)bytes.mutableBytes + copied, message->msg_iov[i].iov_base, part);
        copied += part;
    }
    if (copied == (size_t)result) {
        socklen_t sourceLength = message->msg_namelen;
        matchInjectedPacket(fd, bytes.bytes, bytes.length, flags, message->msg_name, &sourceLength);
        message->msg_namelen = sourceLength;
    }
    return result;
}

%ctor {
    sg_discoveryLock = [NSObject new];
    sg_bonjourTargets = [NSMutableArray array];
    sg_injectedPackets = [NSMutableArray array];
    sg_rounds = [NSMutableArray array];
    sg_bridgeQueue = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
    SGRebindImport("sendto", bridgeSendTo, (void **)&sg_originalSendTo);
    SGRebindImport("sendmsg", bridgeSendMsg, (void **)&sg_originalSendMsg);
    SGRebindImport("recvfrom", bridgeRecvFrom, (void **)&sg_originalRecvFrom);
    SGRebindImport("recvmsg", bridgeRecvMsg, (void **)&sg_originalRecvMsg);
    dispatch_async(dispatch_get_main_queue(), ^{
        sg_targetBrowser = [SGConnectTargetBrowser new];
        [sg_targetBrowser start];
    });
}
