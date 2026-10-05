// Head gestures: AirPods' motion (CMHeadphoneMotionManager, iOS 14) read while a song plays, handed to the detector
// of SGHeadDetector.h, and what it finds done as a gesture of the player (Gestures.h's SGGesturePerform).
//
// The sensors cost the AirPods' battery, so the manager runs only while the switch is on and a song is playing, and
// for a minute after it pauses so a nod can resume it. The attitude it reports is relative to wherever the headphones
// started, which the detector does not mind: it follows a slow average of the head and reads only the swing around it.
//
// Threading: everything but the motion handler is main thread. The handler runs on a serial queue of this file's,
// which owns the detector and the calibrator; the main thread reaches them only by adding an operation to that queue.
#import <CoreMotion/CoreMotion.h>
#import <stdatomic.h>
#import "Core/SGCore.h"
#import "Headers/SPTPlayer.h"
#import "Shared/Player/PlayerState.h"
#import "HeadGestures.h"
#import "SGHeadDetector.h"

// How long after a song pauses the sensors are still listened to.
static const NSTimeInterval kListenAfterPause = 60;

static double radians(NSInteger degrees) {
    return (double)degrees * M_PI / 180.0;
}

static NSInteger degreesSetting(NSString *key, NSInteger fallback) {
    return MAX(SGHeadDegreesMin, MIN(SGHeadDegreesMax, SGInt(key, fallback)));
}

static SGGestureAction actionSetting(NSString *key, SGGestureAction fallback) {
    NSInteger value = SGInt(key, fallback);
    return value >= SGGestureNothing && value <= SGGestureRepeat ? (SGGestureAction)value : fallback;
}

@interface SGHeadMotion : NSObject <CMHeadphoneMotionManagerDelegate, SGPlayerStateObserver>
+ (instancetype)shared;
- (void)configure;
- (void)reconcile;
- (NSString *)status;
- (void)calibrateAxis:(NSInteger)axis seconds:(NSTimeInterval)seconds done:(void (^)(BOOL, NSInteger))done;
@end

@implementation SGHeadMotion {
    CMHeadphoneMotionManager *_manager;
    NSOperationQueue *_queue;
    // Main thread.
    BOOL _playing, _connected, _running, _denied;
    NSDate *_pausedAt;
    void (^_calibrationDone)(BOOL, NSInteger);
    // The queue's alone, and the two switches the queue reads, set from the queue's own operations.
    SGHeadDetector _detector;
    SGHeadCalibrator _calibrator;
    atomic_bool _detecting, _calibrating;
}

+ (instancetype)shared {
    static SGHeadMotion *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [SGHeadMotion new]; });
    return shared;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _queue = [NSOperationQueue new];
    _queue.name = @"spotifyglass.headgestures";
    _queue.maxConcurrentOperationCount = 1;
    _queue.qualityOfService = NSQualityOfServiceUserInitiated;
    SGHeadDetectorInit(&_detector, radians(SGHeadNodDegreesDefault), radians(SGHeadShakeDegreesDefault));
    SGHeadCalibratorBegin(&_calibrator);
    return self;
}

#pragma mark - settings

// The thresholds and the switch to the queue, so the detector starts over with them.
- (void)configure {
    BOOL on = SGFlag(SGKeyHeadGestures, NO);
    double nod = radians(degreesSetting(SGKeyHeadNodDegrees, SGHeadNodDegreesDefault));
    double shake = radians(degreesSetting(SGKeyHeadShakeDegrees, SGHeadShakeDegreesDefault));
    [_queue addOperationWithBlock:^{
        SGHeadDetectorInit(&self->_detector, nod, shake);
        atomic_store(&self->_detecting, on);
    }];
}

- (BOOL)wantsSensors {
    if (_calibrationDone) return YES;
    if (!SGFlag(SGKeyHeadGestures, NO)) return NO;
    return _playing || (_pausedAt && -[_pausedAt timeIntervalSinceNow] < kListenAfterPause);
}

- (void)reconcile {
    BOOL want = [self wantsSensors];
    if (want && !_running) [self start];
    else if (!want && _running) [self stop];
}

#pragma mark - the sensors

- (void)start {
    CMAuthorizationStatus authorization = CMHeadphoneMotionManager.authorizationStatus;
    _denied = authorization == CMAuthorizationStatusDenied || authorization == CMAuthorizationStatusRestricted;
    if (_denied) return;
    if (!_manager) {
        _manager = [CMHeadphoneMotionManager new];
        _manager.delegate = self;
    }
    __weak typeof(self) weakSelf = self;
    [_manager startDeviceMotionUpdatesToQueue:_queue withHandler:^(CMDeviceMotion *motion, NSError *error) {
        [weakSelf handle:motion error:error];
    }];
    _running = YES;
    SGLog(@"head gestures: listening, motion available %d", _manager.isDeviceMotionAvailable);
}

- (void)stop {
    [_manager stopDeviceMotionUpdates];
    _running = NO;
    _connected = NO;
    [_queue addOperationWithBlock:^{ SGHeadDetectorReset(&self->_detector); }];
    SGLog(@"head gestures: stopped");
}

// On the queue.
- (void)handle:(CMDeviceMotion *)motion error:(NSError *)error {
    if (error || !motion) return;
    double time = motion.timestamp, pitch = motion.attitude.pitch, yaw = motion.attitude.yaw;
    if (atomic_load(&_calibrating)) {
        SGHeadCalibratorFeed(&_calibrator, time, pitch, yaw);
        return;
    }
    if (!atomic_load(&_detecting)) return;
    SGHeadEvent event = SGHeadDetectorFeed(&_detector, time, pitch, yaw);
    if (event == SGHeadEventNone) return;
    dispatch_async(dispatch_get_main_queue(), ^{ [self fire:event]; });
}

- (void)headphoneMotionManagerDidConnect:(CMHeadphoneMotionManager *)manager {
    dispatch_async(dispatch_get_main_queue(), ^{ self->_connected = YES; });
}

- (void)headphoneMotionManagerDidDisconnect:(CMHeadphoneMotionManager *)manager {
    dispatch_async(dispatch_get_main_queue(), ^{ self->_connected = NO; });
    [_queue addOperationWithBlock:^{ SGHeadDetectorReset(&self->_detector); }];
}

#pragma mark - what a gesture does

- (void)fire:(SGHeadEvent)event {
    if (!SGFlag(SGKeyHeadGestures, NO) || _calibrationDone) return;
    BOOL nod = event == SGHeadEventNod;
    SGGestureAction action = nod ? actionSetting(SGKeyHeadNodAction, SGGesturePlayPause)
                                 : actionSetting(SGKeyHeadShakeAction, SGGestureNextTrack);
    SGLog(@"head gestures: %@, action %ld", nod ? @"nod" : @"shake", (long)action);
    if (action == SGGestureNothing) return;
    SGGesturePerform(action);
    // A tap on the phone says the gesture was read, for a phone that is in a pocket.
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
}

#pragma mark - the player

- (void)playerStateDidChange:(SPTPlayerState *)state {
    BOOL playing = state.isPlaying && !state.isPaused;
    if (playing == _playing) return;
    _playing = playing;
    if (!playing) {
        NSDate *paused = _pausedAt = [NSDate date];
        // The sensors stand down a minute after the pause, unless it has ended by then.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((kListenAfterPause + 1) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (self->_pausedAt == paused) [self reconcile];
        });
    }
    [self reconcile];
}

#pragma mark - learning a person's swing

- (void)calibrateAxis:(NSInteger)axis seconds:(NSTimeInterval)seconds done:(void (^)(BOOL, NSInteger))done {
    if (_calibrationDone || (axis != 0 && axis != 1)) {
        if (done) done(NO, 0);
        return;
    }
    _calibrationDone = [done copy];
    [_queue addOperationWithBlock:^{
        SGHeadCalibratorBegin(&self->_calibrator);
        SGHeadCalibratorSetAxis(&self->_calibrator, (int)axis);
        atomic_store(&self->_calibrating, true);
    }];
    [self reconcile];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self finishCalibration:axis];
    });
}

- (void)finishCalibration:(NSInteger)axis {
    [_queue addOperationWithBlock:^{
        atomic_store(&self->_calibrating, false);
        double threshold = 0;
        BOOL found = SGHeadCalibratorResult(&self->_calibrator, (int)axis, &threshold);
        dispatch_async(dispatch_get_main_queue(), ^{
            NSInteger degrees = 0;
            if (found) {
                degrees = (NSInteger)llround(threshold * 180.0 / M_PI);
                SGSetInt(axis == 0 ? SGKeyHeadNodDegrees : SGKeyHeadShakeDegrees, degrees);
            }
            void (^done)(BOOL, NSInteger) = self->_calibrationDone;
            self->_calibrationDone = nil;
            [self configure];
            [self reconcile];
            if (done) done(found, degrees);
        });
    }];
}

#pragma mark - what the page says

- (NSString *)status {
    if (!SGFlag(SGKeyHeadGestures, NO)) return @"Off";
    if (_denied) return @"Motion access refused";
    if (!_running) return @"Waiting for a song";
    return _connected ? @"Listening" : @"Waiting for AirPods";
}

@end

void SGHeadGesturesApply(void) {
    dispatch_block_t apply = ^{
        SGHeadMotion *motion = [SGHeadMotion shared];
        SGAddPlayerStateObserver(motion);
        [motion configure];
        [motion reconcile];
    };
    if (NSThread.isMainThread) apply();
    else dispatch_async(dispatch_get_main_queue(), apply);
}

NSString *SGHeadGesturesStatus(void) {
    return [SGHeadMotion shared].status;
}

void SGHeadGesturesCalibrate(NSInteger axis, NSTimeInterval seconds, void (^done)(BOOL found, NSInteger degrees)) {
    [[SGHeadMotion shared] calibrateAxis:axis seconds:seconds done:done];
}

// Listening starts once the app is up, with the state the player has reported by then.
%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{ SGHeadGesturesApply(); });
}
