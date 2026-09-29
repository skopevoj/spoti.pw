// Spotify's audio chain rebuilt with real Core Audio units in the simulator (AudioUnitDriver2: a converter fed
// by a render callback, a mixer and RemoteIO, wired with MakeConnection, slices of 4096), with AudioEffects.x,
// its settings, its libraries and the engine compiled in. The harness is the main executable, so its
// AudioOutputUnitStart goes through the rebound import slot exactly as Spotify's does. A second render
// notify, added after the output started and so after the effects', reads what they left in the buffer, and
// a script of settings checks the level it measures.
//
// The generator plays a 440 Hz sine at -12 dBFS peak in the left channel and nothing in the right, so a
// channel swap shows as well as a gain.
//
//     THEOS=$HOME/theos ../build-sim.sh
//     xcrun simctl install <udid> build/sim/AudioEffectsHarness.app
//     xcrun simctl launch --console-pty <udid> com.vojta.audioeffectsharness
#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <stdatomic.h>
#import "Shared/AudioEffects/AudioEffects.h"

static const float kAmplitude = 0.25f;

static atomic_bool sg_mute;
static atomic_uint_fast64_t sg_phase;
static double sg_generatorRate;

static OSStatus generate(void *refCon, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *timestamp, UInt32 bus,
                         UInt32 frames, AudioBufferList *data) {
    uint64_t start = atomic_fetch_add(&sg_phase, frames);
    BOOL mute = atomic_load(&sg_mute);
    float *left = data->mBuffers[0].mData, *right = data->mNumberBuffers > 1 ? data->mBuffers[1].mData : NULL;
    for (UInt32 i = 0; i < frames; i++) {
        left[i] = mute ? 0 : kAmplitude * sinf(2 * M_PI * 440 * (start + i) / sg_generatorRate);
        if (right) right[i] = 0;
    }
    if (mute) *flags |= kAudioUnitRenderAction_OutputIsSilence;
    return noErr;
}

#pragma mark - the probe, after the effects' notify

enum { kProbeCalls = 64 };
typedef struct { float left, right; UInt32 frames; bool silent; } ProbeCall;
static ProbeCall sg_calls[kProbeCalls];
static atomic_uint sg_callCount;

static OSStatus probe(void *refCon, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *timestamp, UInt32 bus,
                      UInt32 frames, AudioBufferList *data) {
    if (!(*flags & kAudioUnitRenderAction_PostRender) || bus != 0 || !frames) return noErr;
    // The notify's buffers are in the unit's output (hardware) format, float with a buffer per channel here,
    // whatever the client format.
    if (data->mNumberBuffers < 2 || data->mBuffers[0].mDataByteSize != frames * sizeof(float)) return noErr;
    const float *l = data->mBuffers[0].mData, *r = data->mBuffers[1].mData;
    double left = 0, right = 0;
    for (UInt32 i = 0; i < frames; i++) {
        left += l[i] * l[i];
        right += r[i] * r[i];
    }
    unsigned n = atomic_load(&sg_callCount);
    sg_calls[n % kProbeCalls] = (ProbeCall){(float)(left / frames), (float)(right / frames), frames, (*flags & kAudioUnitRenderAction_OutputIsSilence) != 0};
    atomic_store(&sg_callCount, n + 1);
    return noErr;
}

// The level of the last `calls` renders, in dB RMS, per channel.
static void level(unsigned calls, double *left, double *right, unsigned *frames, unsigned *silentCalls) {
    unsigned n = atomic_load(&sg_callCount);
    double l = 0, r = 0;
    unsigned count = 0;
    *frames = 0;
    *silentCalls = 0;
    for (unsigned i = 0; i < calls && i < n && i < kProbeCalls; i++) {
        ProbeCall call = sg_calls[(n - 1 - i) % kProbeCalls];
        l += call.left;
        r += call.right;
        *frames = call.frames;
        *silentCalls += call.silent;
        count++;
    }
    *left = count ? 10 * log10(l / count + 1e-20) : -200;
    *right = count ? 10 * log10(r / count + 1e-20) : -200;
}

static int sg_failures;

static void report(NSString *what, double wantLeft, double wantRight) {
    double left, right;
    unsigned frames, silent;
    level(8, &left, &right, &frames, &silent);
    BOOL ok = (isnan(wantLeft) || fabs(left - wantLeft) < 0.6) && (isnan(wantRight) || fabs(right - wantRight) < 0.6);
    if (!ok) sg_failures++;
    NSLog(@"[harness] %@ %-44@ left %6.1f dB, right %6.1f dB (want %@, %@), slices of %u, %u silent; status \"%@\"", ok ? @"  ok  " : @"FAILED",
          what, left, right, isnan(wantLeft) ? @"any" : [NSString stringWithFormat:@"%.1f", wantLeft],
          isnan(wantRight) ? @"any" : [NSString stringWithFormat:@"%.1f", wantRight], frames, silent, SGDSPStatus());
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

@interface SGDSPHarnessDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation SGDSPHarnessDelegate {
    AudioUnit _converter, _mixer, _output;
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
    check(AudioUnitAddRenderNotify(_output, probe, NULL), "probe");
    [self logScopes];
}

// What the client format is and what the notify gets: the output scope, the hardware's.
- (void)logScopes {
    AudioStreamBasicDescription client = {0}, hardware = {0};
    UInt32 size = sizeof client;
    AudioUnitGetProperty(_output, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &client, &size);
    size = sizeof hardware;
    AudioUnitGetProperty(_output, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &hardware, &size);
    NSLog(@"[harness] RemoteIO's client format %.0f Hz %u-bit flags 0x%x; its output side, which the notifies get, %.0f Hz %u-bit flags 0x%x",
          client.mSampleRate, (unsigned)client.mBitsPerChannel, (unsigned)client.mFormatFlags, hardware.mSampleRate,
          (unsigned)hardware.mBitsPerChannel, (unsigned)hardware.mFormatFlags);
}

// Another client format: 16-bit interleaved at another rate, converter straight into RemoteIO. The notify
// still gets the output side's float, now with the engine following the rate change.
- (void)startInt16ChainAt:(double)rate {
    AudioOutputUnitStop(_output);
    AudioUnitRemoveRenderNotify(_output, probe, NULL);
    AudioUnit old[] = {_output, _mixer, _converter};
    for (int i = 0; i < 3; i++) {
        if (!old[i]) continue;
        AudioUnitUninitialize(old[i]);
        AudioComponentInstanceDispose(old[i]);
    }
    sg_generatorRate = rate;
    _converter = make(kAudioUnitType_FormatConverter, kAudioUnitSubType_AUConverter);
    _output = make(kAudioUnitType_Output, kAudioUnitSubType_RemoteIO);
    _mixer = NULL;
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
    check(AudioUnitAddRenderNotify(_output, probe, NULL), "probe");
    [self logScopes];
}

- (void)after:(double)seconds do:(void (^)(void))block {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [UIViewController new];
    [self.window makeKeyAndVisible];
    [AVAudioSession.sharedInstance setCategory:AVAudioSessionCategoryPlayback error:nil];
    [AVAudioSession.sharedInstance setActive:YES error:nil];
    double sine = 20 * log10(kAmplitude / M_SQRT2), nothing = -200, any = NAN;
    NSLog(@"[harness] the sine's level is %.1f dB RMS in the left channel", sine);
    SGDSPSetSwitch(SGKeyDSP, NO);
    [self startSpotifyChainAt:44100];

    NSArray *script = @[
        @[@"master off", ^{}, @(sine), @(nothing)],
        @[@"master off, post gain -12 dB (bypassed)", ^{ SGDSPSetNumber(SGKeyDSPPostGain, -12); }, @(sine), @(nothing)],
        @[@"master on, post gain -12 dB", ^{ SGDSPSetSwitch(SGKeyDSP, YES); }, @(sine - 12), @(nothing)],
        @[@"post gain back to 0 dB, every effect off", ^{ SGDSPSetNumber(SGKeyDSPPostGain, 0); }, @(sine), @(nothing)],
        @[@"Liveprog swapChannels.eel from the library", ^{
            SGDSPSetString(SGKeyDSPLiveprogFile, @"swapChannels.eel");
            SGDSPSetSwitch(SGKeyDSPLiveprog, YES);
        }, @(nothing), @(sine)],
        @[@"Liveprog off, reverb on (plate)", ^{
            SGDSPSetSwitch(SGKeyDSPLiveprog, NO);
            SGDSPSetSwitch(SGKeyDSPReverb, YES);
        }, @(any), @(any)],
        @[@"the source goes silent, the reverb rings out", ^{ atomic_store(&sg_mute, true); }, @(any), @(any)],
        @[@"reverb off, silent: silence", ^{ SGDSPSetSwitch(SGKeyDSPReverb, NO); }, @(nothing), @(nothing)],
        @[@"a convolver file not in the library", ^{
            atomic_store(&sg_mute, false);
            SGDSPSetString(SGKeyDSPConvolverFile, @"missing.wav");
            SGDSPSetSwitch(SGKeyDSPConvolver, YES);
        }, @(sine), @(nothing)],
        @[@"16-bit interleaved at 48 kHz, post gain -12 dB", ^{
            SGDSPSetSwitch(SGKeyDSPConvolver, NO);
            SGDSPSetNumber(SGKeyDSPPostGain, -12);
            [self startInt16ChainAt:48000];
        }, @(sine - 12), @(nothing)],
        @[@"16-bit, Liveprog swapChannels.eel", ^{
            SGDSPSetNumber(SGKeyDSPPostGain, 0);
            SGDSPSetSwitch(SGKeyDSPLiveprog, YES);
        }, @(nothing), @(sine)],
        @[@"master off again", ^{ SGDSPSetSwitch(SGKeyDSP, NO); }, @(sine), @(nothing)],
    ];
    __block NSString *label = nil;
    __block double wantLeft = 0, wantRight = 0;
    double step = 2.5, at = 1;
    for (NSArray *entry in script) {
        [self after:at do:^{
            if (label) report(label, wantLeft, wantRight);
            if ([label hasPrefix:@"the source goes silent"]) {
                // The tail: the level over the renders since the source stopped, loud at first, then less.
                double left, right;
                unsigned frames, silent;
                level(3, &left, &right, &frames, &silent);
                NSLog(@"[harness]        the tail's last renders: left %.1f dB, right %.1f dB, %u of them flagged silent", left, right, silent);
            }
            if ([label hasPrefix:@"a convolver file"]) {
                NSString *error = SGDSPError(SGKeyDSPConvolver);
                if (!error) sg_failures++;
                NSLog(@"[harness] %@ its error: \"%@\"", error ? @"  ok  " : @"FAILED", error);
            }
            label = entry[0];
            wantLeft = [entry[2] doubleValue];
            wantRight = [entry[3] doubleValue];
            ((void (^)(void))entry[1])();
        }];
        if ([entry[0] hasPrefix:@"the source goes silent"]) {
            // Right after the source stops, the reverb's tail is still coming out.
            [self after:at + 0.4 do:^{
                double left, right;
                unsigned frames, silent;
                level(2, &left, &right, &frames, &silent);
                BOOL ringing = left > -80 || right > -80;
                if (!ringing) sg_failures++;
                NSLog(@"[harness] %@ 0.4 s after the source stopped: left %.1f dB, right %.1f dB, %u of 2 renders flagged silent after the effects",
                      ringing ? @"  ok  " : @"FAILED", left, right, silent);
            }];
        }
        at += step;
    }
    [self after:at do:^{
        report(label, wantLeft, wantRight);
        NSLog(@"[harness] %@: %d failed", sg_failures ? @"FAILED" : @"all passed", sg_failures);
        exit(sg_failures ? 1 : 0);
    }];
    return YES;
}

@end

// Every audio effects key back to what it holds until set, and a script of the harness's own in the
// Liveprog library, before anything reads them.
__attribute__((constructor(101))) static void sgr_harnessDefaults(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    for (NSString *key in defaults.dictionaryRepresentation.allKeys) {
        if ([key hasPrefix:@"spotifyglass.dsp"]) [defaults removeObjectForKey:key];
    }
    NSString *swap = @"desc: swap the channels\n@sample\nt = spl0;\nspl0 = spl1;\nspl1 = t;\n";
    [swap writeToFile:[SGDSPLibraryDirectory(SGDSPFileLiveprog) stringByAppendingPathComponent:@"swapChannels.eel"] atomically:YES
             encoding:NSUTF8StringEncoding error:nil];
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(SGDSPHarnessDelegate.class));
    }
}
