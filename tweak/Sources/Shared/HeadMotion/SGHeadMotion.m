// SGHeadMotion.h says what this is for.
#import "Core/SGCore.h"
#import "SGHeadMotion.h"

@interface SGHeadMotionHub : NSObject <CMHeadphoneMotionManagerDelegate>
@property (nonatomic, strong) CMHeadphoneMotionManager *manager;
@property (nonatomic, strong) NSOperationQueue *queue;
@property (nonatomic, strong) NSMutableDictionary<NSUUID *, SGHeadMotionHandler> *handlers;
@property (atomic) BOOL connected;
@end

@implementation SGHeadMotionHub

+ (instancetype)shared {
    static SGHeadMotionHub *hub;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ hub = [SGHeadMotionHub new]; });
    return hub;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _queue = [NSOperationQueue new];
    _queue.maxConcurrentOperationCount = 1;
    _queue.name = @"spotifyglass.headmotion";
    _queue.qualityOfService = NSQualityOfServiceUserInteractive;
    _handlers = [NSMutableDictionary dictionary];
    return self;
}

- (void)headphoneMotionManagerDidConnect:(CMHeadphoneMotionManager *)manager {
    self.connected = YES;
    SGLog(@"head motion: headphones connected");
}

- (void)headphoneMotionManagerDidDisconnect:(CMHeadphoneMotionManager *)manager {
    self.connected = NO;
    SGLog(@"head motion: headphones disconnected");
}

// Main thread: the manager is started and stopped from there only.
- (void)update {
    BOOL wanted;
    @synchronized (self) { wanted = self.handlers.count > 0; }
    if (wanted && !self.manager) {
        CMHeadphoneMotionManager *manager = [CMHeadphoneMotionManager new];
        if (!manager.isDeviceMotionAvailable) {
            SGLog(@"head motion: not available on this iPhone");
            return;
        }
        manager.delegate = self;
        self.manager = manager;
        __weak SGHeadMotionHub *weakSelf = self;
        [manager startDeviceMotionUpdatesToQueue:self.queue withHandler:^(CMDeviceMotion *motion, NSError *error) {
            SGHeadMotionHub *hub = weakSelf;
            if (!hub || !motion) return;
            hub.connected = YES;
            NSArray<SGHeadMotionHandler> *handlers;
            @synchronized (hub) { handlers = hub.handlers.allValues; }
            for (SGHeadMotionHandler handler in handlers) handler(motion);
        }];
        SGLog(@"head motion: started");
    } else if (!wanted && self.manager) {
        [self.manager stopDeviceMotionUpdates];
        self.manager.delegate = nil;
        self.manager = nil;
        self.connected = NO;
        SGLog(@"head motion: stopped");
    }
}

@end

static void onMain(dispatch_block_t block) {
    if (NSThread.isMainThread) block();
    else dispatch_async(dispatch_get_main_queue(), block);
}

id SGHeadMotionAddObserver(SGHeadMotionHandler handler) {
    if (!handler) return nil;
    SGHeadMotionHub *hub = SGHeadMotionHub.shared;
    NSUUID *token = [NSUUID UUID];
    @synchronized (hub) { hub.handlers[token] = [handler copy]; }
    onMain(^{ [hub update]; });
    return token;
}

void SGHeadMotionRemoveObserver(id token) {
    if (![token isKindOfClass:NSUUID.class]) return;
    SGHeadMotionHub *hub = SGHeadMotionHub.shared;
    @synchronized (hub) { [hub.handlers removeObjectForKey:token]; }
    onMain(^{ [hub update]; });
}

BOOL SGHeadMotionSupported(void) {
    return YES;   // CMHeadphoneMotionManager is iOS 14's, below the mod's floor
}

BOOL SGHeadMotionConnected(void) {
    return SGHeadMotionHub.shared.connected;
}
