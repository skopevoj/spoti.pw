#import "Core/SGCore.h"
#import "SGSingController.h"
#import "SGSingAudio.h"
#import "SGSingFormat.h"
#import "SGSingModel.h"
#import "SGStemWorker.h"
#import "Shared/Audio/SGAudioPipeline.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/SpeedPitch.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

NSString *const SGSingDidChangeNotification = @"spotifyglass.singChanged";
static BOOL sg_configured;

// The control state is polled this often while Sing has work; the audio and lyric clocks are render-driven.
static const NSTimeInterval kReconcileInterval = 0.1;
// How often the system's now playing is handed the audible clock again while the mix runs late of the source.
static const NSTimeInterval kClockPublication = 0.25;
// Play is announced before Spotify builds its local audio graph, so a missing graph is waited for this long.
static const NSTimeInterval kGraphWait = 3;
// A seek or a skip has this long to land before Sing gives up preparing the new position.
static const NSTimeInterval kCommandWait = 5;

static NSString *trackOf(SPTPlayerState *state) { return SGURIString(state.track.URI); }
static BOOL isSong(NSString *uri) { return [uri hasPrefix:@"spotify:track:"]; }
static BOOL notPlaying(SPTPlayerState *state) { return state.isPaused || !state.isPlaying; }
static BOOL overheated(void) { return NSProcessInfo.processInfo.thermalState >= NSProcessInfoThermalStateCritical; }
// Everything between the source and the ear, in source seconds: the output route, and speed and pitch's unit.
static double downstreamLatency(void) {
    return (AVAudioSession.sharedInstance.outputLatency + SGPlayerAudioLatency()) * SGPlayerSpeed();
}

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
@property (nonatomic) NSString *model;
@property (nonatomic) uint64_t generation;
@property (nonatomic) float level, reduced;
@property (nonatomic) BOOL wanted, interrupted, cooling;
@property (nonatomic) NSTimer *timer;
@property (nonatomic) CFTimeInterval lastClockPublication;
- (void)workerStatus:(int32_t)status session:(SGSingSession *)session;
- (void)reconcile;
- (void)stop:(BOOL)discard unload:(BOOL)unload;
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
    // Without its voice model Sing is unavailable and shows nothing; Mod Settings > Karaoke says why and gets it.
    _model = SGSingModelPath();
    _state = _model ? SGSingIdle : SGSingUnavailable;
    SGAddPlayerStateObserver(self);
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserver:self selector:@selector(modelChanged:) name:SGSingModelDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(memory:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    [nc addObserver:self selector:@selector(thermal:) name:NSProcessInfoThermalStateDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(route:) name:AVAudioSessionRouteChangeNotification object:nil];
    [nc addObserver:self selector:@selector(interruption:) name:AVAudioSessionInterruptionNotification object:nil];
    return self;
}
- (void)publish:(SGSingState)state explanation:(NSString *)explanation {
    // Retained audio still draining after the model went must not bring the microphone back.
    if (!_model) { state = SGSingUnavailable; explanation = nil; }
    if (_state == state && ((_explanation == explanation) || [_explanation isEqualToString:explanation])) return;
    SGLog(@"Sing state %lu -> %lu, thermal %ld%@", (unsigned long)_state, (unsigned long)state,
          (long)NSProcessInfo.processInfo.thermalState, explanation ? [@": " stringByAppendingString:explanation] : @"");
    _state = state; _explanation = explanation;
    [NSNotificationCenter.defaultCenter postNotificationName:SGSingDidChangeNotification object:nil];
}
- (NSString *)restriction {
    if (_interrupted) return @"Sing will be ready when the audio interruption ends.";
    if (overheated()) return @"Let your iPhone cool down before using Sing again.";
    for (AVAudioSessionPortDescription *port in AVAudioSession.sharedInstance.currentRoute.outputs)
        if ([port.portType isEqualToString:AVAudioSessionPortAirPlay]) return @"Sing is unavailable over AirPlay.";
    if (!isSong(trackOf(SGPlayerState()))) return @"Play a song on this iPhone to use Sing.";
    return nil;
}
- (void)startTimer {
    if (_timer) return;
    __weak typeof(self) weak = self;
    _timer = [NSTimer timerWithTimeInterval:kReconcileInterval repeats:YES block:^(NSTimer *timer) { [weak reconcile]; }];
    _timer.tolerance = kReconcileInterval / 5;
    [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
}
- (void)prepareNextTrack:(SPTPlayerState *)state {
    SGSingSession *session = _session;
    if (!session || session.retiring || ![session.track isEqualToString:trackOf(state)]) return;
    id next = [state respondsToSelector:@selector(future)] ? state.future.firstObject : nil;
    SPTPlayerOptions *options = [state respondsToSelector:@selector(options)] ? state.options : nil;
    if ([options respondsToSelector:@selector(repeatingTrack)] && options.repeatingTrack) next = state.track;
    NSString *uri = [next respondsToSelector:@selector(URI)] ? SGURIString([next URI]) : nil;
    if (!isSong(uri)) uri = nil;
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
        _cooling = overheated();
        [self publish:SGSingFailed explanation:reason]; return;
    }
    SPTPlayerState *state = SGPlayerState();
    // Loading/pausing the player is not a request to turn Sing off. Model preparation is
    // independent of the render callback and can complete before the user presses Play.
    if (state.isLoading) { [self publish:SGSingPreparing explanation:nil]; [self startTimer]; return; }
    SGSingSession *session = [SGSingSession new];
    session.finished = YES;
    session.track = trackOf(state);
    session.audio = SGSingAudioCreate((SGAudioStamp){++_generation, SGSingTrackIdentifier(session.track), 0, 1, 0},
                                      SGSingWindowFrames, SGSingHopFrames, _level);
    if (!session.audio) { _blockedTrack = session.track; [self publish:SGSingFailed explanation:@"There is not enough memory to start Sing."]; return; }
    SGSingStreamSetModelReady(stream(session), false);
    _session = session;
    [self prepareNextTrack:state];
    session.finished = NO;
    void *context = (__bridge_retained void *)session;
    session.worker = SGStemWorkerStart(context, _model.fileSystemRepresentation, SGSingWindowFrames, SGSingHopFrames,
                                       readPCM, writePCM, workerStatus);
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
    if (state.isLoading || ![session.track isEqualToString:trackOf(state)]) return;
    SGSingAudioSetClock(session.audio, SGSingSourcePosition(state), SGSingTrackIdentifier(session.track));
    SGSingAudioSetLatency(session.audio, downstreamLatency());
    SGSingStreamPause(stream(session), notPlaying(state));
    session.attached = SGSingAudioAttach(session.audio);
    if (notPlaying(state)) {
        session.attachDeadline = 0;
        [self publish:session.ready ? SGSingReady : SGSingPreparing explanation:nil];
    } else if (!session.attached) {
        // Retain the loaded worker while the graph settles; a missing graph on the first poll is
        // not a bad format.
        CFTimeInterval now = CACurrentMediaTime();
        if (!session.attachDeadline) {
            session.attachDeadline = now + kGraphWait;
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
        if (!_wanted || (!_interrupted && [self restriction]) || ![session.track isEqualToString:trackOf(SGPlayerState())]) {
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
// What the running stream's timeline says, published as the state; stopping when it has gone idle.
- (void)followStream:(SGSingSession *)session state:(SPTPlayerState *)state {
    SGSingTimelineState current = SGSingStreamState(stream(session));
    if (current == SGSingTimelineIdle) {
        BOOL failed = _state == SGSingFailed;
        [self stop:YES unload:NO];
        if (!failed) [self publish:_wanted ? SGSingPreparing : SGSingIdle explanation:nil];
        return;
    }
    if (session.retiring) return;
    if (current == SGSingTimelineDraining) {
        [self streamStopped:session];
    } else if (current == SGSingTimelineRecovering) {
        if (_state != SGSingRecovering)
            SGLog(@"Sing waiting for vocals: ready %llu, queued %llu", (unsigned long long)SGSingStreamReadyFrames(stream(session)),
                  (unsigned long long)SGSingStreamQueued(stream(session)));
        [self publish:SGSingRecovering explanation:nil];
    } else if (current == SGSingTimelineActive) {
        [self publish:SGSingActive explanation:nil];
    } else {
        [self publish:session.ready && notPlaying(state) ? SGSingReady : SGSingPreparing explanation:nil];
    }
}
- (void)reconcile {
    SGSingSession *session = _session;
    if (session) {
        SPTPlayerState *state = SGPlayerState();
        SGSingStreamPause(stream(session), notPlaying(state) || _interrupted);
        [self attachSession:session];
        if (!_interrupted && session.attached && !SGAudioPipelineSourceProcessorAttached(session.audio)) {
            SGSingAudioInvalidate(); [self stop:YES unload:NO];
            [self publish:SGSingPreparing explanation:nil];
        } else if (session.attached) {
            // Repeat-one has no URI change to notify observers. Its verified sample boundary
            // still resets the audible clock without replacing the running separator.
            if (!session.retiring && [session.nextTrack isEqualToString:session.track] &&
                SGSingAudioContinueTrack(session.audio, SGSingTrackIdentifier(trackOf(state)))) {
                session.nextTrack = nil;
                [self prepareNextTrack:state];
                SGLog(@"Sing continuing a prepared repeat of the current track");
            }
            SGSingAudioSetLatency(session.audio, downstreamLatency());
            if (CACurrentMediaTime() - _lastClockPublication >= kClockPublication) {
                _lastClockPublication = CACurrentMediaTime();
                [self prepareNextTrack:state];
                MPNowPlayingInfoCenter *center = MPNowPlayingInfoCenter.defaultCenter;
                NSDictionary *info = center.nowPlayingInfo;
                if (info) center.nowPlayingInfo = info;
            }
            [self followStream:session state:state];
        }
    }
    if (_waitingForCommand) {
        SPTPlayerState *state = SGPlayerState();
        BOOL changed = _commandTrack ? ![_commandTrack isEqualToString:trackOf(state)] : fabs(SGSingSourcePosition(state) - _seekTarget) < 0.3;
        if (state && !state.isLoading && changed) _waitingForCommand = NO;
        else if (CACurrentMediaTime() > _commandDeadline) {
            _waitingForCommand = NO; _blockedTrack = trackOf(state);
            [self publish:SGSingFailed explanation:@"Playback changed. Tap Sing to prepare the current position."];
        }
    }
    if (!_session && _wanted && !_waitingForCommand && !_blockedTrack) [self start];
    if (!_session && !_waitingForCommand && !_retired.count &&
        (!_wanted || _blockedTrack || [self restriction])) { [_timer invalidate]; _timer = nil; }
}
- (void)playerStateDidChange:(SPTPlayerState *)state {
    NSString *track = trackOf(state);
    if (_blockedTrack && ![_blockedTrack isEqualToString:track]) _blockedTrack = nil;
    if (_session && ![_session.track isEqualToString:track]) {
        if (!_session.retiring && [_session.nextTrack isEqualToString:track] &&
            SGSingAudioContinueTrack(_session.audio, SGSingTrackIdentifier(track))) {
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
- (void)memory:(NSNotification *)note {
    _blockedTrack = trackOf(SGPlayerState()); [self stop:NO unload:YES];
    if (_state != SGSingUnavailable) [self publish:SGSingFailed explanation:@"Sing stopped to free memory. The original audio will continue."];
}
- (void)thermal:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!overheated()) {
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
        // Spotify owns whether playback resumes. Retain the model and queued audio across a
        // temporary interruption; reconcile pauses the worker's source input.
        // If Spotify replaces its audio graph, reattach a fresh generation after the interruption.
        [self reconcile];
    });
}
// Unavailable without the model, and back to off once it is there.
- (void)updateAvailability {
    if (!_model) [self publish:SGSingUnavailable explanation:nil];
    else if (_state == SGSingUnavailable) [self publish:SGSingIdle explanation:nil];
}
// The model downloaded or removed from Mod Settings > Karaoke. Going, it takes Sing with it: the original audio
// still retained plays out in order, and the warm model is let go before its files are.
- (void)modelChanged:(NSNotification *)note {
    NSString *model = SGSingModelPath();
    if (model == _model || [model isEqualToString:_model]) return;
    _model = model;
    if (!model) {
        _wanted = NO; _blockedTrack = nil; _waitingForCommand = NO;
        [self stop:NO unload:YES];
    }
    [self updateAvailability];
}
// Sing's switch, turned while Spotify runs. Off stops the work the same way and leaves nothing on screen.
- (void)setConfigured:(BOOL)configured {
    if (configured) { [self updateAvailability]; return; }
    _wanted = NO; _blockedTrack = nil; _waitingForCommand = NO;
    [self stop:NO unload:YES];
    [self publish:SGSingUnavailable explanation:nil];
}
// A seek or a skip replaces the running generation; Sing prepares the new position once it lands.
- (void)awaitCommand:(NSString *)track seek:(double)seconds {
    _commandTrack = track; _seekTarget = seconds;
    _waitingForCommand = _wanted && (track != nil || !isnan(seconds));
    _commandDeadline = CACurrentMediaTime() + kCommandWait;
    [self stop:YES unload:NO];
    [self reconcile];
}
@end

BOOL SGSingSupported(void) {
    if (@available(iOS 27.0, *)) return YES;
    return NO;
}
void SGSingConfigure(BOOL enabled) {
    enabled = enabled && SGSingSupported();
    if (enabled == sg_configured) return;
    sg_configured = enabled;
    if (enabled && !sg_controller) sg_controller = [SGSingController new];
    [sg_controller setConfigured:enabled];
    // What SGSingAvailable answers changes with the switch even where the controller's own state does not.
    [NSNotificationCenter.defaultCenter postNotificationName:SGSingDidChangeNotification object:nil];
}
SGSingState SGSingCurrentState(void) { return sg_configured ? sg_controller.state : SGSingUnavailable; }
BOOL SGSingAvailable(void) { return SGSingCurrentState() != SGSingUnavailable; }
NSString *SGSingExplanation(void) { return [sg_controller restriction] ?: sg_controller.explanation; }
BOOL SGSingCanRetry(void) {
    return sg_configured && sg_controller.state != SGSingUnavailable && !sg_controller.session &&
        !sg_controller.retired.count && ![sg_controller restriction] && !SGPlayerState().isLoading;
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
        [sg_controller publish:SGSingPreparing explanation:nil];
    }
    [sg_controller reconcile];
}
void SGSingPlaybackWillChange(void) { SGSingAudioInvalidate(); }
void SGSingPlaybackDidChange(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!sg_controller.session && sg_controller.waitingForCommand) { [sg_controller reconcile]; return; }
        [sg_controller awaitCommand:sg_controller.session.track seek:NAN];
    });
}
void SGSingPlaybackDidSeek(double seconds) {
    dispatch_async(dispatch_get_main_queue(), ^{ [sg_controller awaitCommand:nil seek:seconds]; });
}
