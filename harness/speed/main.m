// Spotify's audio chain (AudioUnitDriver2: a converter fed by a render callback, a mixer, RemoteIO, wired
// with MakeConnection and slices of 4096) rebuilt with real units in the simulator, with
// PlayerSpeedPitch.x's rebinding, render callback and SPTPlayerState hook running on it for real. The
// converter's callback stands in for Spotify's decoder and counts what it hands over, so the log shows
// how fast the song is drained at each speed, and how far a mock player state's position drifts from it.
// A notify on the output counts the sine's zero crossings, so it shows the pitch that plays as well: 440 Hz
// unless Pitch moves it or pitch follows speed.
//
//     THEOS=$HOME/theos ./build.sh && xcrun simctl install booted build/SpeedHarness.app
//     xcrun simctl launch --console-pty booted com.vojta.speedharness
#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <stdatomic.h>

double SGPlayerSpeed(void);
void SGSetPlayerSpeed(double speed);
void SGSetPlayerPitch(float semitones);
BOOL SGPlayerSpeedAllowed(void);
void SGSetPlayerPitchFollowsSpeed(BOOL follows);

static const double kRate = 44100;
static atomic_uint_fast64_t sg_decoded;
// What the output played: frames and the sine's rising zero crossings in them, at the hardware's rate.
static atomic_uint_fast64_t sg_played, sg_crossings;
static double sg_outputRate;
static float sg_lastSample;

// Spotify's player state as far as -position goes (disassembly of -[SPTPlayerState position]).
@interface SPTPlayerState : NSObject
@property (nonatomic) double positionAsOfTimestamp;
@property (nonatomic, strong) NSDate *timestamp;
@end

@implementation SPTPlayerState
- (double)playbackSpeed {
    return 1;
}
- (double)position {
    return MAX(0, self.positionAsOfTimestamp - self.timestamp.timeIntervalSinceNow * [self playbackSpeed]);
}
@end

static OSStatus decoder(void *refCon, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *timestamp, UInt32 bus,
                        UInt32 frames, AudioBufferList *data) {
    uint64_t start = atomic_fetch_add(&sg_decoded, frames);
    for (UInt32 i = 0; i < frames; i++) {
        float value = 0.05f * sinf(2 * M_PI * 440 * (start + i) / kRate);
        for (UInt32 b = 0; b < data->mNumberBuffers; b++) ((float *)data->mBuffers[b].mData)[i] = value;
    }
    return noErr;
}

static OSStatus played(void *refCon, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *timestamp, UInt32 bus,
                       UInt32 frames, AudioBufferList *data) {
    if (!(*flags & kAudioUnitRenderAction_PostRender) || bus != 0 || !data || !data->mNumberBuffers || !data->mBuffers[0].mData) return noErr;
    const float *samples = data->mBuffers[0].mData;
    UInt32 stride = data->mBuffers[0].mNumberChannels ?: 1, crossings = 0;
    for (UInt32 i = 0; i < frames; i++) {
        float sample = samples[i * stride];
        if (sg_lastSample < 0 && sample >= 0) crossings++;
        sg_lastSample = sample;
    }
    atomic_fetch_add(&sg_crossings, crossings);
    atomic_fetch_add(&sg_played, frames);
    return noErr;
}

static AudioUnit make(OSType type, OSType subType) {
    AudioComponentDescription description = {type, subType, kAudioUnitManufacturer_Apple, 0, 0};
    AudioUnit unit = NULL;
    AudioComponentInstanceNew(AudioComponentFindNext(NULL, &description), &unit);
    return unit;
}

static void check(OSStatus status, const char *what) {
    if (status) NSLog(@"[harness] %s failed: %d", what, (int)status);
}

@interface SGRHarnessDelegate : UIResponder <UIApplicationDelegate, UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation SGRHarnessDelegate {
    SPTPlayerState *_state;
    uint64_t _lastDecoded, _settledPlayed, _settledCrossings;
    NSTimeInterval _lastAt, _startedAt;
}

- (void)startChain {
    [AVAudioSession.sharedInstance setCategory:AVAudioSessionCategoryPlayback error:nil];
    [AVAudioSession.sharedInstance setActive:YES error:nil];
    AudioUnit converter = make(kAudioUnitType_FormatConverter, kAudioUnitSubType_AUConverter);
    AudioUnit mixer = make(kAudioUnitType_Mixer, kAudioUnitSubType_MultiChannelMixer);
    AudioUnit output = make(kAudioUnitType_Output, kAudioUnitSubType_RemoteIO);
    AURenderCallbackStruct callback = {decoder, NULL};
    check(AudioUnitSetProperty(converter, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback, sizeof callback), "callback");
    AudioUnitConnection toMixer = {converter, 0, 0}, toOutput = {mixer, 0, 0};
    check(AudioUnitSetProperty(mixer, kAudioUnitProperty_MakeConnection, kAudioUnitScope_Input, 0, &toMixer, sizeof toMixer), "connect mixer");
    check(AudioUnitSetProperty(output, kAudioUnitProperty_MakeConnection, kAudioUnitScope_Input, 0, &toOutput, sizeof toOutput), "connect output");
    AudioStreamBasicDescription format = {kRate, kAudioFormatLinearPCM, kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved, 4, 1, 4, 2, 32, 0};
    check(AudioUnitSetProperty(converter, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, sizeof format), "converter in");
    check(AudioUnitSetProperty(converter, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &format, sizeof format), "converter out");
    check(AudioUnitSetProperty(mixer, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, sizeof format), "mixer in");
    check(AudioUnitSetProperty(mixer, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &format, sizeof format), "mixer out");
    check(AudioUnitSetProperty(output, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, sizeof format), "output in");
    UInt32 slice = 4096;
    AudioUnit units[] = {converter, mixer, output};
    for (int i = 0; i < 3; i++) check(AudioUnitSetProperty(units[i], kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &slice, sizeof slice), "slice");
    for (int i = 0; i < 3; i++) check(AudioUnitInitialize(units[i]), "initialize");
    AudioStreamBasicDescription hardware = {0};
    UInt32 size = sizeof hardware;
    check(AudioUnitGetProperty(output, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &hardware, &size), "hardware format");
    if (hardware.mFormatFlags & kAudioFormatFlagIsFloat) {
        sg_outputRate = hardware.mSampleRate;
        check(AudioUnitAddRenderNotify(output, played, NULL), "notify");
    } else {
        NSLog(@"[harness] the output is not float (flags 0x%x), its pitch is not measured", (unsigned)hardware.mFormatFlags);
    }
    check(AudioOutputUnitStart(output), "start");
}

- (void)report:(NSString *)what {
    NSTimeInterval now = CACurrentMediaTime();
    uint64_t decoded = atomic_load(&sg_decoded), frames = atomic_load(&sg_played), crossings = atomic_load(&sg_crossings);
    double content = decoded / kRate;
    // The pitch from a second into the step on, once a unit switched in has played out its start.
    double pitch = frames > _settledPlayed && sg_outputRate > 0 ? (crossings - _settledCrossings) * sg_outputRate / (frames - _settledPlayed) : 0;
    NSLog(@"[harness] %-28@ decoder drained %.2fx over the last %.1f s, then playing %.1f Hz; content %.2f s, state position %.2f s (off %+.0f ms), state speed %.2f",
          what, (decoded - _lastDecoded) / kRate / (now - _lastAt), now - _lastAt, pitch, content, _state.position,
          (_state.position - content) * 1000, [_state playbackSpeed]);
    _lastDecoded = decoded;
    _lastAt = now;
}

// The player reporting: a state whose position is what the decoder has handed over, as of now.
- (void)playerReports {
    _state = [SPTPlayerState new];
    _state.positionAsOfTimestamp = atomic_load(&sg_decoded) / kRate;
    _state.timestamp = [NSDate date];
}

- (void)after:(double)seconds do:(void (^)(void))block {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}

- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *config = [[UISceneConfiguration alloc] initWithName:@"Harness" sessionRole:session.role];
    config.delegateClass = self.class;
    return config;
}

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController = [UIViewController new];
    [self.window makeKeyAndVisible];
    [self startChain];
    NSLog(@"[harness] speed allowed: %d", SGPlayerSpeedAllowed());
    [self after:1 do:^{
        [self playerReports];
        self->_lastDecoded = atomic_load(&sg_decoded);
        self->_settledPlayed = atomic_load(&sg_played);
        self->_settledCrossings = atomic_load(&sg_crossings);
        self->_lastAt = CACurrentMediaTime();
    }];
    // At, what, speed, pitch, pitch follows speed.
    NSArray *script = @[
        @[@3, @"normal", @1, @0, @NO],
        @[@6, @"1.5x", @1.5, @0, @NO],
        @[@9, @"1.5x, +3 st", @1.5, @3, @NO],
        @[@12, @"1.5x, pitch follows", @1.5, @0, @YES],
        @[@15, @"0.75x, pitch follows", @0.75, @0, @YES],
        @[@18, @"0.75x, +3 st", @0.75, @3, @NO],
        @[@21, @"back to normal", @1, @0, @NO],
        @[@24, @"normal, unit out", @1, @0, @NO],
    ];
    __block NSString *label = @"normal";
    for (NSArray *step in script) {
        [self after:[step[0] doubleValue] do:^{
            [self report:label];
            label = step[1];
            SGSetPlayerPitchFollowsSpeed([step[4] boolValue]);
            SGSetPlayerSpeed([step[2] doubleValue]);
            SGSetPlayerPitch([step[3] floatValue]);
        }];
        [self after:[step[0] doubleValue] + 1 do:^{
            self->_settledPlayed = atomic_load(&sg_played);
            self->_settledCrossings = atomic_load(&sg_crossings);
        }];
        // A report mid step, the way Spotify's player reports now and then.
        [self after:[step[0] doubleValue] + 1.5 do:^{ [self playerReports]; }];
    }
    [self after:27 do:^{
        [self report:label];
        exit(0);
    }];
}

@end

__attribute__((constructor(101))) static void sgr_harnessDefaults(void) {
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"spotifyglass.redesign"];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"spotifyglass.speedPitch.follows"];
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(SGRHarnessDelegate.class));
    }
}
