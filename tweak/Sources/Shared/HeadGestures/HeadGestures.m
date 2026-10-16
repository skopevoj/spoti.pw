// HeadGestures.h says what this is.
#import "Core/SGCore.h"
#import "Headers/SPTPlayer.h"
#import "Shared/HeadMotion/SGHeadMotion.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Haptics/Haptics.h"
#import "Shared/Player/SGLibrary.h"
#import "SGHeadGestureDetector.h"
#import "HeadGestures.h"

static id sg_token;
// The head queue's own.
static SGHeadGestureDetector sg_detector;

static NSString *actionName(SGHeadGestureAction action) {
    switch (action) {
        case SGHeadGestureActionNothing: return @"nothing";
        case SGHeadGestureActionPlayPause: return @"play/pause";
        case SGHeadGestureActionNext: return @"next";
        case SGHeadGestureActionPrevious: return @"previous";
        case SGHeadGestureActionRestart: return @"restart";
        case SGHeadGestureActionLike: return @"like";
    }
    return @"?";
}

// Main thread. Only Play/pause and Like answer while nothing plays: a skip nobody hears is a skip by accident.
static void run(SGHeadGestureAction action) {
    if (action == SGHeadGestureActionNothing) return;
    id<SPTPlayer> player = SGKaraokePlayer();
    SPTPlayerState *state = SGPlayerState();
    if (!player || !state.track) {
        SGLog(@"airpods gestures: %@, but there is no player or track", actionName(action));
        return;
    }
    BOOL paused = [state respondsToSelector:@selector(isPaused)] ? state.isPaused : NO;
    if (paused && action != SGHeadGestureActionPlayPause && action != SGHeadGestureActionLike) return;
    id result = nil;
    switch (action) {
        case SGHeadGestureActionPlayPause: {
            SEL command = paused ? @selector(resume:) : @selector(pause:);
            if (![player respondsToSelector:command]) break;
            result = paused ? [player resume:nil] : [player pause:nil];
            SGPlayFeedback(paused ? SGFeedbackPlay : SGFeedbackPause);
            break;
        }
        case SGHeadGestureActionNext:
            if ([player respondsToSelector:@selector(skipToNextTrackWithOptions:)]) result = [player skipToNextTrackWithOptions:nil];
            SGPlayFeedback(SGFeedbackSkip);
            break;
        case SGHeadGestureActionPrevious:
            if ([player respondsToSelector:@selector(skipToPreviousTrackWithOptions:)]) result = [player skipToPreviousTrackWithOptions:nil];
            SGPlayFeedback(SGFeedbackSkip);
            break;
        case SGHeadGestureActionRestart:
            if ([player respondsToSelector:@selector(seekTo:)]) [player seekTo:0];
            SGPlayFeedback(SGFeedbackSkip);
            break;
        case SGHeadGestureActionLike: {
            NSString *uri = SGURIString(state.track.URI);
            NSString *track = [uri hasPrefix:@"spotify:track:"] ? [uri substringFromIndex:@"spotify:track:".length] : nil;
            SGLibrarySaveTrack(track, YES, ^(BOOL saved) { if (saved) SGPlayFeedback(SGFeedbackAdd); });
            break;
        }
        default:
            break;
    }
    SGLog(@"airpods gestures: %@ -> %@", actionName(action), result);
}

static void feed(CMDeviceMotion *motion) {
    SGHeadGesture gesture = SGHeadGestureFeed(&sg_detector, motion.timestamp, motion.attitude.pitch, motion.attitude.yaw);
    if (gesture == SGHeadGestureNone) return;
    SGHeadGestureAction action = gesture == SGHeadGestureNod
        ? (SGHeadGestureAction)SGInt(SGKeyHeadGestureNod, SGHeadGestureActionLike)
        : (SGHeadGestureAction)SGInt(SGKeyHeadGestureShake, SGHeadGestureActionNext);
    SGLog(@"airpods gestures: %@", gesture == SGHeadGestureNod ? @"nod" : @"shake");
    dispatch_async(dispatch_get_main_queue(), ^{ run(action); });
}

void SGHeadGesturesApply(void) {
    BOOL wanted = SGFlag(SGKeyHeadGestures, NO) && SGHeadMotionSupported();
    if (wanted && !sg_token) {
        // Reset on the head queue's side of the token: no reading has come in yet.
        sg_detector.nodScale = MAX(30, MIN(200, SGInt(SGKeyHeadGestureNodScale, 100))) / 100.0f;
        sg_detector.shakeScale = MAX(30, MIN(200, SGInt(SGKeyHeadGestureShakeScale, 100))) / 100.0f;
        SGHeadGestureReset(&sg_detector);
        sg_token = SGHeadMotionAddObserver(^(CMDeviceMotion *motion) { feed(motion); });
        SGLog(@"airpods gestures: following the head");
    } else if (!wanted && sg_token) {
        SGHeadMotionRemoveObserver(sg_token);
        sg_token = nil;
        SGLog(@"airpods gestures: stopped");
    }
}

void SGHeadGesturesMeasure(NSTimeInterval seconds, void (^done)(NSNumber *nodSpeed, NSNumber *shakeSpeed)) {
    __block SGHeadGestureDetector watch = {0};
    __block float nod = 0, shake = 0;
    __block BOOL any = NO;
    // The head queue writes these and the main queue reads them only after the token is gone.
    id token = SGHeadMotionAddObserver(^(CMDeviceMotion *motion) {
        SGHeadGestureFeed(&watch, motion.timestamp, motion.attitude.pitch, motion.attitude.yaw);
        any = YES;
        nod = MAX(nod, (float)fabs(watch.pitchRate));
        shake = MAX(shake, (float)fabs(watch.yawRate));
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SGHeadMotionRemoveObserver(token);
        // Give the queue a moment to finish a reading already under way.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            done(any ? @(nod) : nil, any ? @(shake) : nil);
        });
    });
}

NSString *SGHeadGesturesSummary(void) {
    return SGFlag(SGKeyHeadGestures, NO) ? @"On" : @"Off";
}
