// Music Haptics on Spotify's audio chain rebuilt with real Core Audio units in the simulator (as harness/audio-effects/sim
// does: a converter fed by a render callback, a mixer and RemoteIO, wired with MakeConnection, slices of 4096),
// with MusicHaptics.x, the analyzer and the Vibrations settings compiled in and fakehaptics.m standing in for Core
// Haptics. The harness is the main executable, so its AudioOutputUnitStart goes through the rebound import slot as
// Spotify's does. The client format is Spotify's, 44.1 kHz float with a buffer per channel; the simulator's
// hardware is 48 kHz, and MusicHaptics.x logs which of the two it listens at.
//
// The generator plays a beat at 120 BPM, a kick on each whole second and a snare on each half, so the analyzer
// hears a kick and a snare a second. A script changes the settings every 6 s and checks what the stand-in was
// asked to play in the 4 s after the change has settled: what each Follows choice leaves out, the strength
// scaling the taps and the rumble, then a 16-bit interleaved client at 48 kHz.
//
//     THEOS=$HOME/theos ../build-sim.sh
//     xcrun simctl install <udid> build/sim/HapticsHarness.app
//     xcrun simctl launch --console-pty <udid> com.vojta.hapticsharness
//
// Built with -DBEFORE against the MusicHaptics.x of before the output format fix (build-sim.sh before), it runs
// only the format steps, which have no settings to change.
#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <stdatomic.h>
#import "Core/SGCore.h"
#import "Shared/Haptics/Haptics.h"
#import "fakehaptics.h"

static atomic_uint_fast64_t sg_frame;
static double sg_generatorRate;

// A kick (a falling sine, 120 to 50 Hz) on each whole second, a snare (noise and 190 Hz) on each half.
static float beatAt(uint64_t frame, double rate) {
    double t = frame / rate, beat = fmod(t, 1.0), half = fmod(t, 0.5);
    float out = 0;
    if (beat < 0.25) {
        double phase = 2 * M_PI * (50 * beat + 70 / 30.0 * (1 - exp(-30 * beat)));
        out += 0.8f * (float)(sin(phase) * exp(-14 * beat));
    }
    if (beat >= 0.5 && half < 0.15) {
        uint32_t noise = (uint32_t)frame;
        noise ^= noise >> 16; noise *= 0x7feb352du; noise ^= noise >> 15; noise *= 0x846ca68bu; noise ^= noise >> 16;
        out += (float)((0.35 * ((noise & 0xffff) / 32768.0 - 1) + 0.3 * sin(2 * M_PI * 190 * half)) * exp(-28 * half));
    }
    return 0.5f * out;
}

static OSStatus generate(void *refCon, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *timestamp, UInt32 bus,
                         UInt32 frames, AudioBufferList *data) {
    uint64_t start = atomic_fetch_add(&sg_frame, frames);
    float *left = data->mBuffers[0].mData, *right = data->mNumberBuffers > 1 ? data->mBuffers[1].mData : NULL;
    for (UInt32 i = 0; i < frames; i++) {
        left[i] = beatAt(start + i, sg_generatorRate);
        if (right) right[i] = left[i];
    }
    return noErr;
}

#pragma mark - the chain

static AudioUnit make(OSType type, OSType subType) {
    AudioComponentDescription description = {type, subType, kAudioUnitManufacturer_Apple, 0, 0};
    AudioUnit unit = NULL;
    AudioComponentInstanceNew(AudioComponentFindNext(NULL, &description), &unit);
    return unit;
}

static void check(OSStatus status, const char *what) {
    if (status) NSLog(@"[harness] %s failed: %d", what, (int)status);
}

static int sg_failures;

@interface HapticsHarnessDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation HapticsHarnessDelegate {
    AudioUnit _converter, _mixer, _output;
}

- (void)stopChain {
    if (_output) AudioOutputUnitStop(_output);
    AudioUnit old[] = {_output, _mixer, _converter};
    for (int i = 0; i < 3; i++) {
        if (!old[i]) continue;
        AudioUnitUninitialize(old[i]);
        AudioComponentInstanceDispose(old[i]);
    }
    _output = _mixer = _converter = NULL;
}

// Spotify's way: float, one buffer per channel, converter -> mixer -> RemoteIO, slices of 4096.
- (void)startSpotifyChainAt:(double)rate {
    sg_generatorRate = rate;
    _converter = make(kAudioUnitType_FormatConverter, kAudioUnitSubType_AUConverter);
    _mixer = make(kAudioUnitType_Mixer, kAudioUnitSubType_MultiChannelMixer);
    _output = make(kAudioUnitType_Output, kAudioUnitSubType_RemoteIO);
    AURenderCallbackStruct callback = {generate, NULL};
    check(AudioUnitSetProperty(_converter, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback, sizeof callback), "callback");
    AudioUnitConnection toMixer = {_converter, 0, 0}, toOutput = {_mixer, 0, 0};
    check(AudioUnitSetProperty(_mixer, kAudioUnitProperty_MakeConnection, kAudioUnitScope_Input, 0, &toMixer, sizeof toMixer), "connect mixer");
    check(AudioUnitSetProperty(_output, kAudioUnitProperty_MakeConnection, kAudioUnitScope_Input, 0, &toOutput, sizeof toOutput), "connect output");
    AudioStreamBasicDescription format = {rate, kAudioFormatLinearPCM, kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved, 4, 1, 4, 2, 32, 0};
    check(AudioUnitSetProperty(_converter, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, sizeof format), "converter in");
    check(AudioUnitSetProperty(_converter, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &format, sizeof format), "converter out");
    check(AudioUnitSetProperty(_mixer, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, sizeof format), "mixer in");
    check(AudioUnitSetProperty(_mixer, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &format, sizeof format), "mixer out");
    check(AudioUnitSetProperty(_output, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, sizeof format), "output in");
    UInt32 slice = 4096;
    AudioUnit units[] = {_converter, _mixer, _output};
    for (int i = 0; i < 3; i++) check(AudioUnitSetProperty(units[i], kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &slice, sizeof slice), "slice");
    for (int i = 0; i < 3; i++) check(AudioUnitInitialize(units[i]), "initialize");
    check(AudioOutputUnitStart(_output), "start");
    [self logScopes];
}

// 16-bit interleaved at another rate, the converter straight into RemoteIO: the notify still gets the output
// side's float, a buffer per channel.
- (void)startInt16ChainAt:(double)rate {
    [self stopChain];
    atomic_store(&sg_frame, 0);
    sg_generatorRate = rate;
    _converter = make(kAudioUnitType_FormatConverter, kAudioUnitSubType_AUConverter);
    _output = make(kAudioUnitType_Output, kAudioUnitSubType_RemoteIO);
    AURenderCallbackStruct callback = {generate, NULL};
    check(AudioUnitSetProperty(_converter, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback, sizeof callback), "callback");
    AudioStreamBasicDescription floats = {rate, kAudioFormatLinearPCM, kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved, 4, 1, 4, 2, 32, 0};
    AudioStreamBasicDescription shorts = {rate, kAudioFormatLinearPCM, kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked, 4, 1, 4, 2, 16, 0};
    check(AudioUnitSetProperty(_converter, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &floats, sizeof floats), "converter in");
    check(AudioUnitSetProperty(_converter, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &shorts, sizeof shorts), "converter out");
    check(AudioUnitSetProperty(_output, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &shorts, sizeof shorts), "output in");
    AudioUnitConnection toOutput = {_converter, 0, 0};
    check(AudioUnitSetProperty(_output, kAudioUnitProperty_MakeConnection, kAudioUnitScope_Input, 0, &toOutput, sizeof toOutput), "connect output");
    check(AudioUnitInitialize(_converter), "initialize converter");
    check(AudioUnitInitialize(_output), "initialize output");
    check(AudioOutputUnitStart(_output), "start");
    [self logScopes];
}

- (void)logScopes {
    AudioStreamBasicDescription client = {0}, hardware = {0};
    UInt32 size = sizeof client;
    AudioUnitGetProperty(_output, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &client, &size);
    size = sizeof hardware;
    AudioUnitGetProperty(_output, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &hardware, &size);
    NSLog(@"[harness] RemoteIO's client format %.0f Hz %u-bit flags 0x%x; its output side, which the notify gets, %.0f Hz %u-bit flags 0x%x",
          client.mSampleRate, (unsigned)client.mBitsPerChannel, (unsigned)client.mFormatFlags, hardware.mSampleRate,
          (unsigned)hardware.mBitsPerChannel, (unsigned)hardware.mFormatFlags);
}

// A timer rather than dispatch_after, whose leeway grows with the delay (a tenth of it) and lets a script's
// later steps fire out of order.
- (void)after:(double)seconds do:(void (^)(void))block {
    [NSTimer scheduledTimerWithTimeInterval:seconds repeats:NO block:^(NSTimer *timer) { block(); }];
}

// What the stand-in played over the last `seconds`, checked against a kick and a snare a second (one more or
// less, for where the window falls), the taps' mean intensity and the rumble's loudest.
- (void)report:(NSString *)what seconds:(double)seconds kicks:(double)kicks snares:(double)snares rumble:(BOOL)rumble
     intensity:(double)intensity level:(double)level {
    FakeHaptics c = FakeHapticsTake();
    double tapMean = c.kicks + c.snares ? c.tapIntensity / (c.kicks + c.snares) : 0;
    BOOL ok = fabs(c.kicks - kicks * seconds) <= 1 && fabs(c.snares - snares * seconds) <= 1 && (rumble ? c.levels > 0 : c.levels == 0)
              && (isnan(intensity) || fabs(tapMean - intensity) <= 0.05) && (isnan(level) || fabs(c.levelMax - level) <= 0.02);
    if (!ok) sg_failures++;
    NSLog(@"[harness] %@ %-36@ %u kicks, %u snares in %.1f s (want %.0f, %.0f), taps %.2f strong on average (want %@), rumble %u levels, "
          @"%.3f at most (want %@)", ok ? @"  ok  " : @"FAILED", what, c.kicks, c.snares, seconds, kicks * seconds, snares * seconds, tapMean,
          isnan(intensity) ? @"any" : [NSString stringWithFormat:@"%.2f", intensity], c.levels, c.levelMax,
          rumble ? (isnan(level) ? @"some" : [NSString stringWithFormat:@"%.3f", level]) : @"none");
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [UIViewController new];
    [self.window makeKeyAndVisible];
    [AVAudioSession.sharedInstance setCategory:AVAudioSessionCategoryPlayback error:nil];
    [AVAudioSession.sharedInstance setActive:YES error:nil];
    [self startSpotifyChainAt:44100];

    // Each step: the change, then after 1.5 s to settle, 4 s measured. The first measures what 100% and
    // Everything play, which the strength steps are held against.
    __block double tap100 = 0, level100 = 0;
    NSMutableArray *steps = [NSMutableArray arrayWithObject:@[@"44.1 kHz client, Everything, 100%", ^{}, ^(double s) {
        FakeHaptics peek = FakeHapticsTake();
        tap100 = peek.kicks + peek.snares ? peek.tapIntensity / (peek.kicks + peek.snares) : 0;
        level100 = peek.levelMax;
        BOOL ok = fabs(peek.kicks - s) <= 1 && fabs(peek.snares - s) <= 1 && peek.levels > 0;
        if (!ok) sg_failures++;
        NSLog(@"[harness] %@ %-36@ %u kicks, %u snares in %.1f s (want %.0f, %.0f), taps %.2f strong on average, rumble %u levels, %.3f at most",
              ok ? @"  ok  " : @"FAILED", @"44.1 kHz client, Everything, 100%", peek.kicks, peek.snares, s, s, s, tap100, peek.levels, level100);
    }]];
#ifndef BEFORE
    void (^set)(NSInteger, NSInteger) = ^(NSInteger follows, NSInteger strength) {
        SGSetInt(SGKeyMusicFollows, follows);
        SGSetInt(SGKeyMusicStrength, strength);
        SGMusicHapticsSettingsChanged();
    };
    [steps addObjectsFromArray:@[
        @[@"Beat: no rumble", ^{ set(SGMusicFollowsBeat, 100); }, ^(double s) {
            [self report:@"Beat: no rumble" seconds:s kicks:1 snares:1 rumble:NO intensity:tap100 level:NAN];
        }],
        @[@"Bass: no snares", ^{ set(SGMusicFollowsBass, 100); }, ^(double s) {
            [self report:@"Bass: no snares" seconds:s kicks:1 snares:0 rumble:YES intensity:NAN level:level100];
        }],
        @[@"Everything at 50%", ^{ set(SGMusicFollowsEverything, 50); }, ^(double s) {
            [self report:@"Everything at 50%" seconds:s kicks:1 snares:1 rumble:YES intensity:tap100 / 2 level:level100 / 2];
        }],
        @[@"Everything at 200%", ^{ set(SGMusicFollowsEverything, 200); }, ^(double s) {
            [self report:@"Everything at 200%" seconds:s kicks:1 snares:1 rumble:YES intensity:NAN level:MIN(1, level100 * 2)];
        }],
        @[@"the switch off", ^{ SGSetMusicHapticsEnabled(NO); }, ^(double s) {
            [self report:@"the switch off" seconds:s kicks:0 snares:0 rumble:NO intensity:NAN level:NAN];
        }],
        @[@"on again, Everything, 100%", ^{
            set(SGMusicFollowsEverything, 100);
            SGSetMusicHapticsEnabled(YES);
        }, ^(double s) {
            [self report:@"on again, Everything, 100%" seconds:s kicks:1 snares:1 rumble:YES intensity:tap100 level:level100];
        }],
    ]];
#endif
    [steps addObject:@[@"16-bit interleaved client at 48 kHz", ^{ [self startInt16ChainAt:48000]; }, ^(double s) {
        [self report:@"16-bit interleaved client at 48 kHz" seconds:s kicks:1 snares:1 rumble:YES intensity:NAN level:NAN];
    }]];

    // The window is measured as it was, however late its ends fired.
    __block double from = 0;
    double at = 0.5;
    for (NSArray *step in steps) {
        [self after:at do:^{
            NSLog(@"[harness] -> %@", step[0]);
            ((void (^)(void))step[1])();
        }];
        [self after:at + 1.5 do:^{
            FakeHapticsTake();
            from = CACurrentMediaTime();
        }];
        [self after:at + 5.5 do:^{ ((void (^)(double))step[2])(CACurrentMediaTime() - from); }];
        at += 6;
    }
    [self after:at do:^{
        NSLog(@"[harness] %@: %d failed", sg_failures ? @"FAILED" : @"all passed", sg_failures);
        exit(sg_failures ? 1 : 0);
    }];
    return YES;
}

@end

// Music Haptics on, and its settings at their defaults, before MusicHaptics.x's constructor reads them; the
// redesign on, which gates it.
__attribute__((constructor(101))) static void sgr_harnessDefaults(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    for (NSString *key in defaults.dictionaryRepresentation.allKeys) {
        if ([key hasPrefix:@"spotifyglass."]) [defaults removeObjectForKey:key];
    }
    [defaults setBool:YES forKey:SGKeyRedesign];
    [defaults setBool:YES forKey:SGKeyMusicHaptics];
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(HapticsHarnessDelegate.class));
    }
}
