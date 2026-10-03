// Apple's Music Haptics follows the Now Playing timeline, including in the background. It needs
// a recording identifier, not PCM. The generated engine remains a separate, foreground-only choice.
// No private Apple setters: Control Center/Accessibility owns the system preference.
#import <MediaAccessibility/MediaAccessibility.h>
#import <MediaPlayer/MediaPlayer.h>
#import <objc/message.h>
#import <dlfcn.h>
#import "Core/SGCore.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/LockScreenArtwork/SGAppleArtwork.h"
#import "Haptics.h"
#import "SystemMusicHaptics.h"
#import "SGHapticTrack.h"

NSNotificationName const SGSystemMusicHapticsDidChangeNotification = @"spotifyglass.systemMusicHapticsChanged";

// Spotify publishes Now Playing from several threads. Only this snapshot crosses that boundary;
// the player observer, requests, cache, settings and status callbacks all run on the main queue.
static NSObject *sg_lock;
static NSDictionary *sg_track, *sg_info;
static NSString *sg_isrc;
static NSNumber *sg_appleID, *sg_previousAppleID;
static CFAbsoluteTime sg_infoAt;
static NSString *sg_uri, *sg_status = @"No song";
static NSDictionary *sg_headers;
static NSCache<NSString *, NSString *> *sg_codes;
static NSURLSessionDataTask *sg_request;
static NSURLSessionDataTask *sg_catalogRequest;
static NSCache<NSString *, NSNumber *> *sg_catalogIDs;
static NSUInteger sg_revision, sg_attempts;
static id sg_statusObserver;
static BOOL sg_hapticPlaying;

static NSString *appleIDKey(void) {
    static NSString *key;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Verified in MediaPlayer's exported symbols and on-device Now Playing. ISRC-only
        // lookup fails in the tested iOS Shazam service despite the catalog having haptics.
        NSString *const *address = (NSString *const *)dlsym(RTLD_DEFAULT, "_MPNowPlayingInfoPropertyiTunesStoreIdentifier");
        if (address) key = *address;
    });
    return key;
}

BOOL SGSystemMusicHapticsAvailable(void) {
    if (@available(iOS 18.0, *)) return NSClassFromString(@"MAMusicHapticsManager") != nil;
    return NO;
}

BOOL SGSystemMusicHapticsSelected(void) {
    return SGSystemMusicHapticsAvailable() && SGFlag(SGKeySystemMusicHaptics, NO);
}

static BOOL systemEnabled(void) {
    if (@available(iOS 18.0, *)) {
        MAMusicHapticsManager *manager = MAMusicHapticsManager.sharedManager;
        // On iOS 27, isActive is the Control Center pause state, and remains YES when the
        // Accessibility enable switch is off. This read-only selector is present in the device's
        // MediaAccessibility binary; older versions without it keep the public API's behavior.
        SEL enabled = NSSelectorFromString(@"musicHapticsEnabled");
        return ![manager respondsToSelector:enabled] ||
            ((BOOL (*)(id, SEL))objc_msgSend)(manager, enabled);
    }
    return NO;
}

BOOL SGSystemMusicHapticsActive(void) {
    if (@available(iOS 18.0, *))
        return SGSystemMusicHapticsSelected() && systemEnabled() && MAMusicHapticsManager.sharedManager.isActive;
    return NO;
}

NSString *SGSystemMusicHapticsStatus(void) {
    if (!SGSystemMusicHapticsAvailable()) return @"Needs iOS 18";
    if (!SGSystemMusicHapticsSelected()) return @"Generated";
    if (!systemEnabled()) return @"Off in iOS";
    if (!SGSystemMusicHapticsActive()) return @"Paused";
    // A status callback can say active even when the catalog reports unavailable and the phone
    // produces no vibration. Do not turn that contradictory result into a claim of playback.
    return sg_hapticPlaying && [sg_status isEqualToString:@"Ready"] ? @"Playing" : sg_status;
}

static void changed(void) {
    [NSNotificationCenter.defaultCenter postNotificationName:SGSystemMusicHapticsDidChangeNotification object:nil];
}

static void observePlayback(void) {
    if (sg_statusObserver) return;
    if (@available(iOS 18.0, *)) {
        sg_statusObserver = [MAMusicHapticsManager.sharedManager addStatusObserver:^(NSString *code, BOOL active) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if ((![code isEqualToString:sg_isrc] && ![code isEqualToString:sg_appleID.stringValue]) ||
                    !SGSystemMusicHapticsSelected()) return;
                sg_hapticPlaying = active;
                changed();
                SGLog(@"system music haptics: %@, playback %@ (%@)", sg_uri, active ? @"active" : @"inactive",
                      UIApplication.sharedApplication.applicationState == UIApplicationStateBackground ? @"background" : @"foreground");
            });
        }];
        // Apple can return nil when Accessibility > Music Haptics is disabled. Try again when
        // it is enabled or the app returns to the foreground, rather than losing status forever.
    }
}

static void resend(void) {
    NSDictionary *info;
    CFAbsoluteTime at;
    @synchronized (sg_lock) { info = sg_info; at = sg_infoAt; }
    if (!info.count) return;
    NSMutableDictionary *now = [info mutableCopy];
    NSNumber *position = info[MPNowPlayingInfoPropertyElapsedPlaybackTime];
    NSNumber *rate = info[MPNowPlayingInfoPropertyPlaybackRate];
    if (position && rate) now[MPNowPlayingInfoPropertyElapsedPlaybackTime] =
        @(position.doubleValue + rate.doubleValue * MAX(0, CFAbsoluteTimeGetCurrent() - at));
    MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = now;
}

static void checkISRC(NSString *code, NSUInteger revision) {
    if (@available(iOS 18.0, *)) {
        [MAMusicHapticsManager.sharedManager checkHapticTrackAvailabilityForMediaMatchingCode:code completionHandler:^(BOOL available) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (revision != sg_revision || !SGSystemMusicHapticsSelected()) return;
                sg_status = available || sg_appleID ? @"Ready" : @"Unavailable";
                SGLog(@"system music haptics: %@, ISRC catalog %@", sg_uri, available ? @"available" : @"unavailable");
                changed();
            });
        }];
    }
}

static void requestAppleID(NSString *code, double duration, NSUInteger revision, BOOL refreshToken) {
    if (!appleIDKey()) { checkISRC(code, revision); return; }
    NSString *cacheKey = [NSString stringWithFormat:@"%@/%.3f", code, duration];
    NSNumber *kept = [sg_catalogIDs objectForKey:cacheKey];
    if (kept) {
        @synchronized (sg_lock) { sg_appleID = kept; }
        sg_status = @"Ready";
        resend();
        changed();
        return;
    }
    SGAppleCatalogToken(refreshToken, ^(NSString *token) {
        if (revision != sg_revision || !SGSystemMusicHapticsSelected()) return;
        if (!token.length) { checkISRC(code, revision); return; }
        NSURLComponents *url = [NSURLComponents componentsWithString:@"https://amp-api.music.apple.com/v1/catalog/us/songs"];
        url.queryItems = @[
            [NSURLQueryItem queryItemWithName:@"filter[isrc]" value:code],
            [NSURLQueryItem queryItemWithName:@"fields[songs]" value:@"isrc,durationInMillis,hasHaptics"],
        ];
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url.URL];
        request.timeoutInterval = 10;
        [request setValue:@"Mozilla/5.0" forHTTPHeaderField:@"User-Agent"];
        [request setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
        [request setValue:@"https://music.apple.com" forHTTPHeaderField:@"Origin"];
        [sg_catalogRequest cancel];
        sg_catalogRequest = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
            NSNumber *identifier = !error && status == 200 ? SGHapticAppleID(data, code, duration) : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (revision != sg_revision || !SGSystemMusicHapticsSelected()) return;
                sg_catalogRequest = nil;
                if (status == 401 && !refreshToken) {
                    requestAppleID(code, duration, revision, YES);
                    return;
                }
                // Preserve the public ISRC path when the optional catalog lookup cannot
                // resolve this recording. Successful catalog IDs need no competing query.
                if (!identifier) { checkISRC(code, revision); return; }
                [sg_catalogIDs setObject:identifier forKey:cacheKey];
                @synchronized (sg_lock) { sg_appleID = identifier; }
                sg_status = @"Ready";
                SGLog(@"system music haptics: exact Apple recording %@ for %@", identifier, code);
                resend();
                changed();
            });
        }];
        [sg_catalogRequest resume];
    });
}

static void resolved(NSString *code, NSUInteger revision) {
    if (revision != sg_revision || !SGSystemMusicHapticsSelected()) return;
    @synchronized (sg_lock) { sg_isrc = code; }
    sg_status = code ? @"Checking" : @"Unavailable";
    changed();
    resend();
    if (!code) return;
    requestAppleID(code, [sg_track[@"duration"] doubleValue], revision, NO);
}

static void requestCode(void) {
    if (!SGSystemMusicHapticsSelected() || !SGHapticTrackURI(sg_uri) || sg_request || sg_isrc || sg_attempts >= 3) return;
    if (!sg_headers[@"authorization"]) {
        sg_status = @"Waiting";
        changed();
        return;
    }
    NSString *uri = sg_uri;
    NSUInteger revision = sg_revision;
    sg_attempts++;
    sg_status = @"Checking";
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:
        [NSURL URLWithString:@"https://spclient.wg.spotify.com/extended-metadata/v0/extended-metadata"]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = SGHapticMetadataRequest(uri);
    request.timeoutInterval = 10;
    request.allHTTPHeaderFields = sg_headers;
    [request setValue:@"application/x-protobuf" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/x-protobuf" forHTTPHeaderField:@"Accept"];
    sg_request = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *body, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        NSString *code = !error && status == 200 ? SGHapticISRCFromResponse(body, uri) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (revision != sg_revision) return;
            sg_request = nil;
            SGLog(@"system music haptics: recording lookup %@, HTTP %ld, %@", uri, (long)status, code ?: @"no match");
            if (code) {
                [sg_codes setObject:code forKey:uri];
                resolved(code, revision);
            } else if (!error && status == 200) {
                resolved(nil, revision);
                // A valid reply without an ISRC is not a transient network failure.
                sg_attempts = 3;
            } else {
                sg_status = @"Unavailable";
                changed();
                // Bounded retries also give Spotify time to replace expired authentication. No
                // retry loop in the audio callback, and a skip invalidates every delayed attempt.
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    if (revision == sg_revision) requestCode();
                });
            }
        });
    }];
    [sg_request resume];
    changed();
}

static void trackChanged(SPTPlayerState *state, BOOL force) {
    NSString *uri = SGURIString(state.track.URI);
    if (!force && (uri == sg_uri || [uri isEqualToString:sg_uri])) return;
    sg_revision++;
    [sg_request cancel];
    sg_request = nil;
    [sg_catalogRequest cancel];
    sg_catalogRequest = nil;
    sg_attempts = 0;
    sg_uri = [uri copy];
    sg_hapticPlaying = NO;
    NSDictionary *metadata = [state.track respondsToSelector:@selector(metadata)] ? state.track.metadata : nil;
    NSString *album = [metadata[@"album_title"] isKindOfClass:NSString.class] ? metadata[@"album_title"] : @"";
    NSDictionary *track = SGHapticTrackURI(uri) ? @{@"uri": uri, @"title": state.track.trackTitle ?: @"",
                                                  @"album": album, @"duration": @(state.duration)} : nil;
    BOOL hadCode;
    @synchronized (sg_lock) { hadCode = sg_isrc.length > 0 || sg_appleID != nil; sg_track = track; sg_isrc = nil; sg_appleID = nil; }
    sg_status = track ? @"Waiting" : @"Unavailable";
    // Remove the previous recording immediately, before any asynchronous result can arrive.
    if (hadCode || SGSystemMusicHapticsSelected()) resend();
    changed();
    if (!track || !SGSystemMusicHapticsSelected()) return;
    NSString *kept = [sg_codes objectForKey:uri];
    if (kept) resolved(kept, sg_revision);
    else requestCode();
}

void SGSystemMusicHapticsSettingsChanged(void) {
    SGSetMusicHapticsEnabled(NO);
    trackChanged(SGPlayerState(), YES);
    SGSetMusicHapticsEnabled(SGFlag(SGKeyMusicHaptics, NO));
}

// Same proven URLSession delegate methods as KaraokeSource.x, but independent of lyrics being
// enabled. Keep only Spotify service headers in memory; never log or persist credentials.
static void rememberHeaders(NSURLSession *session, NSURLRequest *request) {
    NSString *host = request.URL.host.lowercaseString;
    if (![host isEqualToString:@"spclient.wg.spotify.com"] && ![host hasSuffix:@"-spclient.spotify.com"]) return;
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    NSSet *wanted = [NSSet setWithArray:@[@"authorization", @"client-token", @"app-platform", @"spotify-app-version", @"user-agent", @"accept-language"]];
    for (NSDictionary *source in @[session.configuration.HTTPAdditionalHeaders ?: @{}, request.allHTTPHeaderFields ?: @{}]) {
        [source enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
            if ([key isKindOfClass:NSString.class] && [value isKindOfClass:NSString.class] && [wanted containsObject:[key lowercaseString]])
                headers[[key lowercaseString]] = value;
        }];
    }
    if (!headers[@"authorization"]) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([headers isEqual:sg_headers]) return;
        sg_headers = [headers copy];
        requestCode();
    });
}

@interface SGSystemHapticsWatcher : NSObject <SGPlayerStateObserver>
@end
@implementation SGSystemHapticsWatcher
- (void)playerStateDidChange:(SPTPlayerState *)state { trackChanged(state, NO); }
@end
static SGSystemHapticsWatcher *sg_watcher;

%hook MPNowPlayingInfoCenter
- (void)setNowPlayingInfo:(NSDictionary *)info {
    NSDictionary *track;
    NSString *code;
    NSNumber *identifier, *previousIdentifier;
    @synchronized (sg_lock) {
        // Other Now Playing hooks can hand our published dictionary back to us. Keep the
        // snapshot free of our identifiers so a later mode/track change cannot resend them.
        sg_info = SGHapticInfoWithAppleID(info, nil, nil, appleIDKey(), nil, sg_previousAppleID);
        sg_infoAt = CFAbsoluteTimeGetCurrent();
        track = sg_track;
        code = sg_isrc;
        identifier = sg_appleID;
        previousIdentifier = sg_previousAppleID;
        if (identifier) sg_previousAppleID = identifier;
    }
    BOOL selected = SGSystemMusicHapticsSelected();
    %orig(SGHapticInfoWithAppleID(info, track, selected ? code : nil,
                                appleIDKey(), selected ? identifier : nil, previousIdentifier));
}
%end

%hook SPTDataLoaderService
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    rememberHeaders(session, task.currentRequest);
    %orig;
}
%end

%hook _TtC26Connectivity_HttpClientKit20HttpClientURLSession
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    rememberHeaders(session, task.currentRequest);
    %orig;
}
%end

%ctor {
    if (!SGSystemMusicHapticsAvailable()) return;
    sg_lock = [NSObject new];
    sg_codes = [NSCache new];
    sg_codes.countLimit = 100;
    sg_catalogIDs = [NSCache new];
    sg_catalogIDs.countLimit = 100;
    sg_watcher = [SGSystemHapticsWatcher new];
    SGAddPlayerStateObserver(sg_watcher);
    %init;
    SGRequireClasses(@[@"MPNowPlayingInfoCenter", @"SPTDataLoaderService", @"_TtC26Connectivity_HttpClientKit20HttpClientURLSession"]);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (@available(iOS 18.0, *)) {
            NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
            __block BOOL wasEnabled = systemEnabled();
            __block BOOL wasActive = MAMusicHapticsManager.sharedManager.isActive;
            void (^settingChanged)(NSNotification *) = ^(NSNotification *note) {
                BOOL enabled = systemEnabled();
                BOOL active = MAMusicHapticsManager.sharedManager.isActive;
                // iOS can repeat this notification as Now Playing changes. Resending metadata
                // for an unchanged state feeds those updates back into the native service.
                if (enabled == wasEnabled && active == wasActive) return;
                wasEnabled = enabled;
                wasActive = active;
                if (enabled) observePlayback();
                sg_hapticPlaying = NO;
                changed();
                SGLog(@"system music haptics: iOS enabled %d, active %d", enabled, active);
                if (SGSystemMusicHapticsActive() && sg_isrc) resolved(sg_isrc, sg_revision);
            };
            [center addObserverForName:MAMusicHapticsManagerActiveStatusDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:settingChanged];
            // The separate enable notification is exported by MediaAccessibility on the tested iOS
            // version but absent from older SDK headers. Resolve it optionally, without an OS setter.
            NSNotificationName const *enabledName = (NSNotificationName const *)dlsym(RTLD_DEFAULT, "MAMusicHapticsEnabledStatusDidChangeNotification");
            if (enabledName && *enabledName)
                [center addObserverForName:*enabledName object:nil queue:NSOperationQueue.mainQueue usingBlock:settingChanged];
            observePlayback();
            [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                observePlayback();
                changed();
                trackChanged(SGPlayerState(), NO);
                requestCode();
            }];
        }
    });
}
