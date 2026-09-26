#import "Core/SGCore.h"
#import "SGSingController.h"
#import "SGSingAudio.h"
#import "SGStemWorker.h"
#import "SGSingBackground.h"
#import "Shared/Audio/SGAudioPipeline.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/SpeedPitch.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

NSString *const SGSingDidChangeNotification = @"spotifyglass.singChanged";
static BOOL sg_configured;

// The callback context owns the session until Finished; the controller owns it while audio is
// attached. Neither endpoint can observe freed storage, including cancellation during model load.
@interface SGSingSession : NSObject
@property (nonatomic) SGSingAudio *audio;
@property (nonatomic) void *worker;
@property (nonatomic) BOOL attached, finished, retiring, loading, ready;
@property (nonatomic) CFTimeInterval attachDeadline;
@property (nonatomic) NSString *track;
@property (nonatomic) NSString *nextTrack;
@end
@implementation SGSingSession
- (void)dealloc {
    NSCAssert(!_attached && _finished, @"Sing endpoints must stop before releasing their storage");
    SGSingAudioDestroy(_audio);
}
@end

@interface SGSingController : NSObject <SGPlayerStateObserver>
@property (nonatomic) SGSingSession *session;
@property (nonatomic) NSMutableSet<SGSingSession *> *retired;
@property (nonatomic) double seekTarget, commandDeadline;
@property (nonatomic) NSString *commandTrack;
@property (nonatomic) NSString *blockedTrack;
@property (nonatomic) BOOL waitingForCommand;
@property (nonatomic) SGSingState state;
@property (nonatomic) NSString *explanation;
@property (nonatomic) NSString *model, *hashes;
@property (nonatomic) BOOL usesCoreML;
@property (nonatomic) uint32_t window;
@property (nonatomic) uint64_t generation;
@property (nonatomic) float level, reduced;
@property (nonatomic) BOOL wanted, active, interrupted, cooling;
@property (nonatomic) NSTimer *timer;
@property (nonatomic) CFTimeInterval lastClockPublication, lastBackgroundProgress;
- (void)workerStatus:(int32_t)status session:(SGSingSession *)session;
- (void)reconcile;
- (void)stop:(BOOL)discard unload:(BOOL)unload;
- (void)requestBackground;
@end
static SGSingController *sg_controller;

uint64_t SGSingTrackIdentifier(id uri) {
    const char *text = SGURIString(uri).UTF8String;
    if (!text) return 0;
    uint64_t hash = 14695981039346656037ULL;
    for (const unsigned char *p = (const unsigned char *)text; *p; p++) hash = (hash ^ *p) * 1099511628211ULL;
    return hash ?: 1;
}
BOOL SGSingPosition(SPTPlayerState *state, double *position) {
    if (!state) return NO;
    uint64_t track = SGSingTrackIdentifier(state.track.URI);
    if (SGSingAudioClock(track, position)) return YES;
    if (SGSingAudioAwaitingTrack(sg_controller.session.audio, track)) { *position = 0; return YES; }
    return NO;
}
static SGSingStream *stream(SGSingSession *session) { return SGSingAudioStream(session.audio); }
static int32_t readPCM(void *context, float *pcm, uint64_t *metadata) {
    SGSingStream *s = stream((__bridge SGSingSession *)context);
    int32_t state = SGSingStreamWorkerState(s);
    if (state <= 0) return state;
    SGAudioStamp stamp;
    if (!SGSingStreamReadLiveInput(s, &stamp, pcm)) return 0;
    metadata[0] = stamp.generation; metadata[1] = stamp.track;
    metadata[2] = stamp.sourceFrame; metadata[3] = stamp.format;
    return stamp.frames;
}
static int32_t writePCM(void *context, const float *pcm, uint32_t frames, uint64_t generation,
                        uint64_t track, uint64_t frame, uint32_t format) {
    SGSingStream *s = stream((__bridge SGSingSession *)context);
    if (SGSingStreamWorkerState(s) < 0) return 0;
    return SGSingStreamWriteVocals(s, (SGAudioStamp){generation, track, frame, format, frames}, pcm) ? 1 : -1;
}
static void workerStatus(void *context, int32_t status) {
    SGSingSession *session = (__bridge SGSingSession *)context;
    dispatch_async(dispatch_get_main_queue(), ^{ [sg_controller workerStatus:status session:session]; });
    if (status == SGStemFinished) CFRelease(context);
}

@implementation SGSingController
- (instancetype)init {
    if (!(self = [super init])) return nil;
    _retired = [NSMutableSet set];
    _level = _reduced = SGSingMinimumVocalLevel;
    _active = UIApplication.sharedApplication.applicationState != UIApplicationStateBackground;
    _state = SGSingIdle;
    NSBundle *bundle = [NSBundle bundleWithPath:[NSBundle.mainBundle pathForResource:@"Sing" ofType:@"bundle"]];
    NSDictionary *manifest = [NSDictionary dictionaryWithContentsOfFile:[bundle pathForResource:@"Sing" ofType:@"plist"]];
    NSString *architecture = manifest[@"Architecture"];
    NSString *backend = manifest[@"Backend"];
    _usesCoreML = [backend isEqualToString:@"CoreMLCPU"] || [backend isEqualToString:@"CoreMLAdaptive"];
    _window = [manifest[@"WindowFrames"] unsignedIntValue];
    _model = [bundle pathForResource:@"separator" ofType:_usesCoreML ? @"mlmodelc" : @"aimodelc"];
    _hashes = [bundle pathForResource:@"hashes" ofType:@"json"];
    if ((backend && !_usesCoreML && ![backend isEqualToString:@"CoreAI"]) || !architecture.length ||
        !SGStemArchitectureMatches(architecture.UTF8String) || !_model || !_hashes || _window != 88200) {
        _state = SGSingUnavailable;
        _explanation = @"Sing requires iOS 27, supported hardware, and the matching local voice model in this build.";
    }
    SGAddPlayerStateObserver(self);
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserver:self selector:@selector(background:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [nc addObserver:self selector:@selector(foreground:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [nc addObserver:self selector:@selector(memory:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    [nc addObserver:self selector:@selector(thermal:) name:NSProcessInfoThermalStateDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(route:) name:AVAudioSessionRouteChangeNotification object:nil];
    [nc addObserver:self selector:@selector(interruption:) name:AVAudioSessionInterruptionNotification object:nil];
    return self;
}
- (void)publish:(SGSingState)state explanation:(NSString *)explanation {
    if (_state == state && ((_explanation == explanation) || [_explanation isEqualToString:explanation])) return;
    SGLog(@"Sing state %lu -> %lu, thermal %ld%@", (unsigned long)_state, (unsigned long)state,
          (long)NSProcessInfo.processInfo.thermalState, explanation ? [@": " stringByAppendingString:explanation] : @"");
    _state = state; _explanation = explanation;
    [NSNotificationCenter.defaultCenter postNotificationName:SGSingDidChangeNotification object:nil];
}
- (NSString *)restriction {
    if (_interrupted) return @"Sing will be ready when the audio interruption ends.";
    if (!_active && !_usesCoreML && !SGSingBackgroundAllowed()) return SGSingBackgroundExplanation();
    if (NSProcessInfo.processInfo.thermalState >= NSProcessInfoThermalStateSerious) return @"Let your iPhone cool down before using Sing again.";
    for (AVAudioSessionPortDescription *port in AVAudioSession.sharedInstance.currentRoute.outputs)
        if ([port.portType isEqualToString:AVAudioSessionPortAirPlay]) return @"Sing is unavailable over AirPlay.";
    SPTPlayerState *state = SGPlayerState();
    if (![SGURIString(state.track.URI) hasPrefix:@"spotify:track:"]) return @"Play a song on this iPhone to use Sing.";
    return nil;
}
- (void)startTimer {
    if (_timer) return;
    __weak typeof(self) weak = self;
    // Audio and lyric clocks are render-driven. This timer only reconciles control state.
    _timer = [NSTimer timerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *timer) { [weak reconcile]; }];
    _timer.tolerance = 0.02;
    [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
}
- (void)prepareNextTrack:(SPTPlayerState *)state {
    SGSingSession *session = _session;
    if (!session || session.retiring || ![session.track isEqualToString:SGURIString(state.track.URI)]) return;
    id next = [state respondsToSelector:@selector(future)] ? state.future.firstObject : nil;
    SPTPlayerOptions *options = [state respondsToSelector:@selector(options)] ? state.options : nil;
    if ([options respondsToSelector:@selector(repeatingTrack)] && options.repeatingTrack) next = state.track;
    NSString *uri = [next respondsToSelector:@selector(URI)] ? SGURIString([next URI]) : nil;
    if (![uri hasPrefix:@"spotify:track:"]) uri = nil;
    if (session.nextTrack == uri || [session.nextTrack isEqualToString:uri]) return;
    session.nextTrack = uri;
    SGSingAudioExpectTrack(session.audio, SGSingTrackIdentifier(uri));
}
- (void)cancelWorker:(SGSingSession *)session unload:(BOOL)unload {
    if (session.worker) { SGStemWorkerCancel(session.worker, unload); session.worker = NULL; }
}
- (void)stop:(BOOL)discard unload:(BOOL)unload {
    if (unload) SGStemWorkerPurge();
    SGSingSession *session = _session;
    if (!session) return;
    session.retiring = YES;
    SGSingStreamBypass(stream(session));
    [self cancelWorker:session unload:unload];
    // A prepared, paused model may be attached to a stopped graph. There is no audio to
    // drain, and waiting for a render callback would make Off hang until the user pressed Play.
    if (discard || !session.attached || (_state == SGSingReady && SGSingStreamQueued(stream(session)) == 0)) {
        SGSingAudioDetach(session.audio); session.attached = NO;
        if (!session.finished) [_retired addObject:session];
        _session = nil;
    }
    [self startTimer];
}
- (void)start {
    if (_retired.count) return;
    NSString *reason = [self restriction];
    if (reason) {
        _cooling = NSProcessInfo.processInfo.thermalState >= NSProcessInfoThermalStateSerious;
        [self publish:SGSingFailed explanation:reason]; return;
    }
    SPTPlayerState *state = SGPlayerState();
    // Loading/pausing the player is not a request to turn Sing off. Model preparation is
    // independent of the render callback and can complete before the user presses Play.
    if (state.isLoading) { [self publish:SGSingPreparing explanation:nil]; [self startTimer]; return; }
    SGSingSession *session = [SGSingSession new];
    session.finished = YES;
    session.track = SGURIString(state.track.URI);
    session.audio = SGSingAudioCreate((SGAudioStamp){++_generation, SGSingTrackIdentifier(state.track.URI), 0, 1, 0}, _window, _window * 3 / 4, _level);
    if (!session.audio) { _blockedTrack = session.track; [self publish:SGSingFailed explanation:@"There is not enough memory to start Sing."]; return; }
    SGSingStreamSetModelReady(stream(session), false);
    _session = session;
    [self prepareNextTrack:state];
    session.finished = NO;
    void *context = (__bridge_retained void *)session;
    session.worker = SGStemWorkerStart(context, _model.fileSystemRepresentation, _hashes.fileSystemRepresentation, _window * 3 / 4, readPCM, writePCM, workerStatus);
    if (!session.worker) {
        CFRelease(context); session.finished = YES; _session = nil; _blockedTrack = session.track;
        [self publish:SGSingFailed explanation:@"The local voice model could not start."];
    } else [self publish:SGSingPreparing explanation:nil];
    [self startTimer];
}
- (void)attachSession:(SGSingSession *)session {
    // Capture while the model loads. The timeline emits original audio until it has a full
    // vocal reserve, so compilation/warm-up and read-ahead no longer happen sequentially.
    if ((!session.loading && !session.ready) || session.attached || session.retiring || _interrupted) return;
    SPTPlayerState *state = SGPlayerState();
    if (state.isLoading || ![session.track isEqualToString:SGURIString(state.track.URI)]) return;
    SGSingAudioSetClock(session.audio, SGSingSourcePosition(state), SGSingTrackIdentifier(state.track.URI));
    SGSingAudioSetLatency(session.audio, (AVAudioSession.sharedInstance.outputLatency + SGPlayerAudioLatency()) * SGPlayerSpeed());
    SGSingStreamPause(stream(session), state.isPaused || !state.isPlaying);
    session.attached = SGSingAudioAttach(session.audio);
    if (state.isPaused || !state.isPlaying) {
        session.attachDeadline = 0;
        [self publish:session.ready ? SGSingReady : SGSingPreparing explanation:nil];
    } else if (!session.attached) {
        // Play is announced before Spotify constructs its local graph. Retain the loaded
        // worker while that settles; a missing graph on the first poll is not a bad format.
        CFTimeInterval now = CACurrentMediaTime();
        if (!session.attachDeadline) {
            session.attachDeadline = now + 3;
            SGLog(@"Sing waiting for the local playback graph");
        }
        if (now < session.attachDeadline) { [self publish:SGSingPreparing explanation:nil]; return; }
        _blockedTrack = session.track; [self stop:YES unload:NO];
        [self publish:SGSingFailed explanation:@"Sing needs a supported Spotify audio source with local 44.1 kHz stereo playback. Start a song on this iPhone and try again."];
    }
}
- (void)workerStatus:(int32_t)status session:(SGSingSession *)session {
    if (status == SGStemFinished) {
        session.finished = YES;
        [_retired removeObject:session];
        [self cancelWorker:session unload:NO];
        if (session != _session) { [self reconcile]; return; }
    }
    if (session != _session || session.retiring) return;
    if (status == SGStemLoading || status == SGStemReady) {
        SPTPlayerState *state = SGPlayerState();
        if (!_wanted || (!_interrupted && [self restriction]) || ![session.track isEqualToString:SGURIString(state.track.URI)]) {
            [self stop:YES unload:NO]; [self reconcile]; return;
        }
        session.loading = YES;
        if (status == SGStemReady) {
            session.ready = YES;
            SGSingStreamSetModelReady(stream(session), true);
        }
        [self attachSession:session];
    } else if (status == SGStemFinished && SGSingStreamStopReason(stream(session)) != SGSingStopNone) {
        // A render-side underrun asks the worker to finish normally. Its final callback can
        // reach main before the polling timer; don't misreport it as a broken voice model.
        [self streamStopped:session];
    } else if (status == SGStemFailed || status == SGStemFinished) {
        _blockedTrack = session.track; [self stop:NO unload:YES];
        [self publish:SGSingFailed explanation:@"Sing stopped because the voice model could not keep processing this song. The original audio will continue."];
    }
}
- (void)streamStopped:(SGSingSession *)session {
    SGSingStopReason reason = SGSingStreamStopReason(stream(session));
    SGLog(@"Sing stream stopped: reason %u, source error %d, queued %llu", reason,
          SGSingStreamSourceError(stream(session)), (unsigned long long)SGSingStreamQueued(stream(session)));
    NSString *explanation = reason == SGSingStopSourceError ?
        @"The audio source stopped supplying Sing. The original audio will continue." :
        @"Sing could not keep up with playback. The original audio will continue.";
    // Keep a healthy, loaded model warm. Reloading it after a scheduling delay adds GPU work
    // and startup latency to a retry; memory/thermal events still purge it immediately.
    _blockedTrack = session.track; [self stop:NO unload:NO];
    [self publish:SGSingFailed explanation:explanation];
}
- (void)reconcile {
    SGSingSession *session = _session;
    if (session) {
        SPTPlayerState *state = SGPlayerState();
        SGSingStreamPause(stream(session), state.isPaused || !state.isPlaying || _interrupted);
        [self attachSession:session];
        if (!_interrupted && session.attached && !SGAudioPipelineSourceProcessorAttached(session.audio)) {
            SGSingAudioInvalidate(); [self stop:YES unload:NO];
            [self publish:SGSingPreparing explanation:nil];
        } else if (session.attached) {
            // Repeat-one has no URI change to notify observers. Its verified sample boundary
            // still resets the audible clock without replacing the running separator.
            if (!session.retiring && [session.nextTrack isEqualToString:session.track] &&
                SGSingAudioContinueTrack(session.audio, SGSingTrackIdentifier(state.track.URI))) {
                session.nextTrack = nil;
                [self prepareNextTrack:state];
                SGLog(@"Sing continuing a prepared repeat of the current track");
            }
            CFTimeInterval now = CACurrentMediaTime();
            if (!_usesCoreML && now - _lastBackgroundProgress >= 1) {
                _lastBackgroundProgress = now;
                double remaining = fmax(0, state.duration - SGSingSourcePosition(state));
                uint64_t completed = SGSingStreamProcessed(stream(session));
                uint64_t remainingFrames = isfinite(remaining) && remaining < (double)(INT64_MAX / 44100) ? (uint64_t)(remaining * 44100) : 0;
                SGSingBackgroundProgress(_generation, completed, remainingFrames ? completed + remainingFrames : 0);
            }
            SGSingAudioSetLatency(session.audio, (AVAudioSession.sharedInstance.outputLatency + SGPlayerAudioLatency()) * SGPlayerSpeed());
            if (CACurrentMediaTime() - _lastClockPublication >= 0.25) {
                _lastClockPublication = CACurrentMediaTime();
                [self prepareNextTrack:state];
                MPNowPlayingInfoCenter *center = MPNowPlayingInfoCenter.defaultCenter;
                NSDictionary *info = center.nowPlayingInfo;
                if (info) center.nowPlayingInfo = info;
            }
            SGSingTimelineState current = SGSingStreamState(stream(session));
            if (current == SGSingTimelineIdle) {
                BOOL failed = _state == SGSingFailed;
                [self stop:YES unload:NO];
                if (!failed) [self publish:_wanted ? SGSingPreparing : SGSingIdle explanation:nil];
            } else if (current == SGSingTimelineDraining && !session.retiring) {
                [self streamStopped:session];
            } else if (current == SGSingTimelineRecovering && !session.retiring) {
                if (_state != SGSingRecovering)
                    SGLog(@"Sing waiting for vocals: ready %llu, queued %llu", (unsigned long long)SGSingStreamReadyFrames(stream(session)),
                          (unsigned long long)SGSingStreamQueued(stream(session)));
                [self publish:SGSingRecovering explanation:nil];
            } else if (current == SGSingTimelineActive && !session.retiring) [self publish:SGSingActive explanation:nil];
            else if (current == SGSingTimelinePreparing && !session.retiring)
                [self publish:session.ready && (state.isPaused || !state.isPlaying) ? SGSingReady : SGSingPreparing explanation:nil];
        }
    }
    if (_waitingForCommand) {
        SPTPlayerState *state = SGPlayerState();
        BOOL changed = _commandTrack ? ![_commandTrack isEqualToString:SGURIString(state.track.URI)] : fabs(SGSingSourcePosition(state) - _seekTarget) < 0.3;
        if (state && !state.isLoading && changed) _waitingForCommand = NO;
        else if (CACurrentMediaTime() > _commandDeadline) {
            _waitingForCommand = NO; _blockedTrack = SGURIString(state.track.URI);
            [self publish:SGSingFailed explanation:@"Playback changed. Tap Sing to prepare the current position."];
        }
    }
    if (!_session && _wanted && !_waitingForCommand && !_blockedTrack) [self start];
    if (!_session && !_waitingForCommand && !_retired.count &&
        (!_wanted || _blockedTrack || [self restriction])) { [_timer invalidate]; _timer = nil; }
    if (!_session && !_retired.count && (!_wanted || _blockedTrack || _interrupted || _cooling)) SGSingBackgroundEnd();
}
- (void)playerStateDidChange:(SPTPlayerState *)state {
    if (_blockedTrack && ![_blockedTrack isEqualToString:SGURIString(state.track.URI)]) _blockedTrack = nil;
    if (_session && ![_session.track isEqualToString:SGURIString(state.track.URI)]) {
        NSString *track = SGURIString(state.track.URI);
        if (!_session.retiring && [_session.nextTrack isEqualToString:track] &&
            SGSingAudioContinueTrack(_session.audio, SGSingTrackIdentifier(state.track.URI))) {
            // The source already crossed a verified natural boundary while its previous tail
            // was audible. Preserve those samples, the ready stems and the loaded worker.
            SGLog(@"Sing continuing the prepared next track with %llu queued frames",
                  (unsigned long long)SGSingStreamQueued(stream(_session)));
            _session.track = track; _session.nextTrack = nil;
        } else {
            SGSingAudioInvalidate(); [self stop:YES unload:NO];
        }
    }
    [self prepareNextTrack:state];
    [self reconcile];
}
- (void)background:(NSNotification *)note {
    SGLog(@"Sing lifecycle inactive: %@, app state %ld", note.name, (long)UIApplication.sharedApplication.applicationState);
    _active = NO;
    // Core ML uses its warm CPU model while inactive, under Spotify's audio background
    // mode. Optional GPU acceleration is limited to foreground predictions.
    if (!_usesCoreML && !SGSingBackgroundAllowed()) {
        [self stop:NO unload:YES];
        if (_state != SGSingUnavailable) [self publish:_session ? SGSingDraining : SGSingIdle explanation:nil];
    }
}
- (void)requestBackground {
    if (_usesCoreML) return;
    __weak typeof(self) weak = self;
    SGSingBackgroundStart(^(BOOL expired) {
        typeof(self) self = weak;
        if (!self || !self.wanted) return;
        if (expired || (!SGSingBackgroundAllowed() && !self.active)) {
            self.blockedTrack = SGURIString(SGPlayerState().track.URI);
            [self stop:NO unload:YES];
            [self publish:SGSingFailed explanation:SGSingBackgroundExplanation()];
        }
        [self reconcile];
    });
}
- (void)foreground:(NSNotification *)note {
    SGLog(@"Sing lifecycle active, interrupted %d", _interrupted);
    _active = YES;
    if (_wanted) [self requestBackground];
    [self reconcile];
}
- (void)memory:(NSNotification *)note {
    _blockedTrack = SGURIString(SGPlayerState().track.URI); [self stop:NO unload:YES];
    if (_state != SGSingUnavailable) [self publish:SGSingFailed explanation:@"Sing stopped to free memory. The original audio will continue."];
}
- (void)thermal:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (NSProcessInfo.processInfo.thermalState < NSProcessInfoThermalStateSerious) {
            if (self.cooling) {
                self.cooling = NO;
                if (self.state == SGSingFailed && !self.session) [self publish:SGSingIdle explanation:nil];
                [self reconcile];
            }
            return;
        }
        // An idle feature must not acquire an error just because the phone warmed up.
        if (!self.session && !self.wanted) return;
        self.cooling = YES;
        [self stop:NO unload:YES];
        if (self.state != SGSingUnavailable) [self publish:SGSingFailed explanation:@"Sing stopped so your iPhone can cool down."];
    });
}
- (void)route:(NSNotification *)note {
    SGSingAudioInvalidate();
    dispatch_async(dispatch_get_main_queue(), ^{
        SGLog(@"Sing route changed: reason %@, outputs %lu", note.userInfo[AVAudioSessionRouteChangeReasonKey],
              (unsigned long)AVAudioSession.sharedInstance.currentRoute.outputs.count);
        [self stop:YES unload:NO];
        if (self.state != SGSingUnavailable) [self publish:SGSingIdle explanation:nil];
        [self reconcile];
    });
}
- (void)interruption:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        SGLog(@"Sing interruption: type %@, reason %@, options %@", note.userInfo[AVAudioSessionInterruptionTypeKey],
              note.userInfo[AVAudioSessionInterruptionReasonKey], note.userInfo[AVAudioSessionInterruptionOptionKey]);
        self.interrupted = [note.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue] == AVAudioSessionInterruptionTypeBegan;
        // Spotify owns whether playback resumes. Retain the model, queued audio and GPU
        // grant across a temporary interruption; reconcile pauses the worker's source input.
        // If Spotify replaces its audio graph, reattach a fresh generation after the interruption.
        [self reconcile];
    });
}
@end

void SGSingConfigure(BOOL enabled) {
    sg_configured = enabled && !SGFlag(SGKeySingKillSwitch, NO);
    if (sg_configured && !sg_controller) sg_controller = [SGSingController new];
}
BOOL SGSingConfigured(void) { return sg_configured; }
SGSingState SGSingCurrentState(void) { return sg_configured ? sg_controller.state : SGSingUnavailable; }
NSString *SGSingExplanation(void) {
    return sg_controller.state == SGSingUnavailable ? sg_controller.explanation :
        [sg_controller restriction] ?: sg_controller.explanation;
}
BOOL SGSingCanRetry(void) {
    SPTPlayerState *state = SGPlayerState();
    return sg_configured && sg_controller.state != SGSingUnavailable && !sg_controller.session &&
        !sg_controller.retired.count && ![sg_controller restriction] && !state.isLoading;
}
BOOL SGSingEnabled(void) { return sg_configured && sg_controller.wanted; }
float SGSingVocalLevel(void) { return sg_controller.level; }
float SGSingReducedLevel(void) { return sg_controller.reduced; }
void SGSingSetVocalLevel(float level) {
    if (!sg_configured) return;
    sg_controller.level = SGSingClampLevel(level);
    if (sg_controller.level < 1) sg_controller.reduced = sg_controller.level;
    if (sg_controller.session) SGSingStreamSetLevel(stream(sg_controller.session), sg_controller.level);
    [NSNotificationCenter.defaultCenter postNotificationName:SGSingDidChangeNotification object:nil];
}
void SGSingSetEnabled(BOOL enabled) {
    if (!sg_configured || sg_controller.state == SGSingUnavailable) return;
    if (enabled && sg_controller.state == SGSingFailed && !SGSingCanRetry()) return;
    sg_controller.wanted = enabled;
    sg_controller.blockedTrack = nil;
    if (!enabled) {
        [sg_controller stop:NO unload:NO];
        [sg_controller publish:sg_controller.session ? SGSingDraining : SGSingIdle explanation:nil];
    } else {
        if (sg_controller.active) [sg_controller requestBackground];
        [sg_controller publish:SGSingPreparing explanation:nil];
    }
    [sg_controller reconcile];
}
void SGSingPlaybackWillChange(void) { SGSingAudioInvalidate(); }
void SGSingPlaybackDidChange(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!sg_controller.session && sg_controller.waitingForCommand) { [sg_controller reconcile]; return; }
        sg_controller.commandTrack = sg_controller.session.track;
        sg_controller.waitingForCommand = sg_controller.wanted && sg_controller.commandTrack != nil;
        sg_controller.commandDeadline = CACurrentMediaTime() + 5;
        [sg_controller stop:YES unload:NO];
        [sg_controller reconcile];
    });
}
void SGSingPlaybackDidSeek(double seconds) {
    dispatch_async(dispatch_get_main_queue(), ^{
        sg_controller.commandTrack = nil; sg_controller.seekTarget = seconds;
        sg_controller.waitingForCommand = sg_controller.wanted;
        sg_controller.commandDeadline = CACurrentMediaTime() + 5;
        [sg_controller stop:YES unload:NO]; [sg_controller reconcile];
    });
}
