// Speed and Pitch (SpeedPitchMenu.x draws them), both done on Spotify's audio, under either look.
//
// Hook ownership is Shared/Audio/SGAudioPipeline.x; this file registers its DSP there.
// Spotify's player takes a speed only for podcasts: for songs its restrictions refuse it (device test,
// 2026-09-18: the slider read "Unavailable here"), its own music speed being a per track setting kept on
// playlist items. So speed, like pitch, is done to the sound, by SGTimePitch between Spotify's mixer and
// its speaker unit.
//
// Spotify's audio (AudioUnitDriver2 in the binary) is a chain of units it wires with MakeConnection:
// converter (fed by its decoder through a render callback), EQ, mixer, RemoteIO. Its import of
// AudioUnitSetProperty is rebound (Core/SGRebind.h), and the one call connecting the mixer to the RemoteIO
// unit's input is answered by the central pipeline's render callback, which pulls the mixer itself. At
// normal speed and pitch the callback passes the mixer's sound straight through. Otherwise it renders the
// time and pitch unit, which pulls the mixer for rate times the frames it hands back, so Spotify's decoder
// is drained that much faster: the song plays faster or slower, at its own pitch unless Pitch moves it.
// Switching the unit in or out skips or repeats its 93 ms, so it stays in for a moment after both return
// to normal, and a finger dragging across normal does not switch it back and forth.
//
// Spotify's clock keeps running at its own speed between the player's reports: -[SPTPlayerState position]
// is positionAsOfTimestamp minus timeIntervalSinceNow times [self playbackSpeed] (disassembly,
// 0x1057735ec), so playbackSpeed is hooked to include this speed, and the scrubber, the lyrics and the lock
// screen move with the sound. That bets the player's reported positions follow what the decoder handed
// over, which is what it counts.
//
// When the connection is never seen, pitch falls back to the way it first shipped: a render notify on the
// RemoteIO unit, registered in the central pipeline before audio effects and Music Haptics, runs each buffer
// through a unit working in place; speed is then unavailable. Those buffers are in the unit's output format,
// the hardware's, not the one Spotify hands the unit (harness/audio-effects/sim), so the fallback's unit is made
// for that one.
//
// Speed and pitch last until Spotify quits.
//
// Threading: the render callback and the notify run on the render thread and touch only atomics and the
// units; Spotify sets its properties and starts its unit on its audio thread; everything else is main
// thread.
#import <AudioToolbox/AudioToolbox.h>
#import <pthread.h>
#import <stdatomic.h>
#import "Core/SGCore.h"
#import "Shared/Audio/SGAudioPipeline.h"
#import "Headers/SPTPlayer.h"
#import "SpeedPitch.h"
#import "SGTimePitch.h"

// The unit stays in this long after speed and pitch both came back to normal.
static const double kOffAfter = 1.5;

#pragma mark - shared between the threads

static float sg_speed = 1, sg_semitones;     // main thread
static atomic_uint sg_speedBits;             // sg_speed for SPTPlayerState, read on any thread

// The unit in use and whether the render thread runs it: in the chain (pull), else in place (pitch only).
static _Atomic(SGTimePitch *) sg_pull, sg_inPlace;
static atomic_bool sg_engaged, sg_busy;
static pthread_mutex_t sg_buildLock = PTHREAD_MUTEX_INITIALIZER;

// The formats when Spotify started its output: the one it hands the RemoteIO unit, which the chain's unit
// feeds, and the unit's output side, the hardware's, which the in place fallback's notify gets.
typedef struct {
    atomic_uint_fast64_t rateBits;
    atomic_uint flags, channels, bytes;
} Format;
static Format sg_client, sg_hardware;

static BOOL tapped(void) {
    return SGAudioPipelineTapped();
}

static float loadFloat(atomic_uint *slot) {
    uint32_t bits = atomic_load(slot);
    float value;
    memcpy(&value, &bits, sizeof value);
    return value;
}

static void storeFloat(atomic_uint *slot, float value) {
    uint32_t bits;
    memcpy(&bits, &value, sizeof bits);
    atomic_store(slot, bits);
}

#pragma mark - the render thread: the chain

static OSStatus pullForUnit(void *context, UInt32 frames, AudioBufferList *data) {
    return SGAudioPipelinePull(frames, data, NULL);
}

static BOOL fitsUnit(const AudioBufferList *data, UInt32 frames, SGTimePitch *unit) {
    if (data->mNumberBuffers != SGTimePitchChannels(unit) || frames > kSGTimePitchMaxFrames) return NO;
    for (UInt32 b = 0; b < data->mNumberBuffers; b++) {
        if (!data->mBuffers[b].mData || data->mBuffers[b].mDataByteSize < frames * sizeof(float)) return NO;
    }
    return YES;
}

// Called only by the central pipeline, before the output-domain processors.
static bool processPull(UInt32 frames, AudioBufferList *data, OSStatus *status) {
    atomic_store(&sg_busy, true);
    SGTimePitch *unit = atomic_load(&sg_pull);
    bool handles = data && atomic_load(&sg_engaged) && unit && fitsUnit(data, frames, unit);
    if (handles) *status = SGTimePitchRender(unit, frames, data);
    // An errored render may already have pulled input. Do not pull it a second time as a fallback.
    atomic_store(&sg_busy, false);
    return handles;
}

#pragma mark - the render thread: in place, the fallback

static float sg_scratch[kSGTimePitchMaxChannels][kSGTimePitchMaxFrames];

static inline float readSample(const void *data, UInt32 index, UInt32 bytes, BOOL isFloat, UInt32 fraction) {
    if (bytes == 4) {
        if (isFloat) return ((const float *)data)[index];
        int32_t value = ((const int32_t *)data)[index];
        return fraction ? (float)((double)value / (double)(1u << fraction)) : (float)(value / 2147483648.0);
    }
    return ((const int16_t *)data)[index] / 32768.0f;
}

static inline void writeSample(void *data, UInt32 index, float value, UInt32 bytes, BOOL isFloat, UInt32 fraction) {
    if (bytes == 4 && isFloat) {
        ((float *)data)[index] = value;
        return;
    }
    value = fmaxf(-1, fminf(value, 1));
    if (bytes == 4) {
        double scale = fraction ? (double)(1u << fraction) : 2147483647.0;
        ((int32_t *)data)[index] = (int32_t)(value * scale);
    } else {
        ((int16_t *)data)[index] = (int16_t)(value * 32767);
    }
}

static void shiftInPlace(SGTimePitch *unit, AudioUnitRenderActionFlags *flags, UInt32 frames, AudioBufferList *data) {
    UInt32 formatFlags = atomic_load_explicit(&sg_hardware.flags, memory_order_relaxed);
    UInt32 bytes = atomic_load_explicit(&sg_hardware.bytes, memory_order_relaxed);
    UInt32 channels = SGTimePitchChannels(unit);
    BOOL isFloat = (formatFlags & kAudioFormatFlagIsFloat) != 0;
    BOOL split = (formatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
    UInt32 fraction = (formatFlags & kLinearPCMFormatFlagsSampleFractionMask) >> kLinearPCMFormatFlagsSampleFractionShift;
    if (frames > kSGTimePitchMaxFrames || (bytes != 2 && bytes != 4)) return;
    if (split ? data->mNumberBuffers != channels : data->mNumberBuffers != 1 || data->mBuffers[0].mNumberChannels != channels) return;
    for (UInt32 b = 0; b < data->mNumberBuffers; b++) {
        if (!data->mBuffers[b].mData || data->mBuffers[b].mDataByteSize < frames * bytes * (split ? 1 : channels)) return;
    }
    // Silence still goes through, so the sound the unit holds plays out rather than coming back later.
    BOOL silent = (*flags & kAudioUnitRenderAction_OutputIsSilence) != 0;

    float *lanes[kSGTimePitchMaxChannels];
    BOOL direct = split && isFloat && bytes == 4 && !silent;
    for (UInt32 c = 0; c < channels; c++) {
        if (direct) {
            lanes[c] = data->mBuffers[c].mData;
            continue;
        }
        lanes[c] = sg_scratch[c];
        const void *source = data->mBuffers[split ? c : 0].mData;
        for (UInt32 i = 0; i < frames; i++) {
            lanes[c][i] = silent ? 0 : readSample(source, split ? i : i * channels + c, bytes, isFloat, fraction);
        }
    }
    if (!SGTimePitchProcess(unit, lanes, frames) || direct) return;
    for (UInt32 c = 0; c < channels; c++) {
        void *target = data->mBuffers[split ? c : 0].mData;
        for (UInt32 i = 0; i < frames; i++) writeSample(target, split ? i : i * channels + c, lanes[c][i], bytes, isFloat, fraction);
    }
    *flags &= ~kAudioUnitRenderAction_OutputIsSilence;
}

static OSStatus rendered(void *refCon, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *timestamp, UInt32 bus,
                         UInt32 frames, AudioBufferList *data) {
    if (!(*flags & kAudioUnitRenderAction_PostRender) || bus != 0 || !data || !data->mNumberBuffers || !frames) return noErr;
    if (tapped() || !atomic_load(&sg_engaged)) return noErr;
    atomic_store(&sg_busy, true);
    SGTimePitch *unit = atomic_load(&sg_inPlace);
    if (atomic_load(&sg_engaged) && unit) shiftInPlace(unit, flags, frames, data);
    atomic_store(&sg_busy, false);
    return noErr;
}

#pragma mark - Spotify's audio thread

// One side of the RemoteIO unit's element 0 into `into`; a side that is not linear PCM is left as it was.
static BOOL readScope(AudioUnit unit, AudioUnitScope scope, Format *into, AudioStreamBasicDescription *format) {
    UInt32 size = sizeof *format;
    OSStatus status = AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, scope, 0, format, &size);
    if (status != noErr || format->mFormatID != kAudioFormatLinearPCM || format->mSampleRate <= 0) return NO;
    uint64_t bits;
    memcpy(&bits, &format->mSampleRate, sizeof bits);
    atomic_store(&into->rateBits, bits);
    atomic_store(&into->flags, format->mFormatFlags);
    atomic_store(&into->channels, format->mChannelsPerFrame);
    atomic_store(&into->bytes, format->mBitsPerChannel / 8);
    return YES;
}

static void readFormat(AudioUnit unit) {
    AudioStreamBasicDescription client = {0}, hardware = {0};
    BOOL clientRead = readScope(unit, kAudioUnitScope_Input, &sg_client, &client);
    BOOL hardwareRead = readScope(unit, kAudioUnitScope_Output, &sg_hardware, &hardware);
    static int logged;
    if (!clientRead || !hardwareRead) {
        if (logged++ < 6) SGLog(@"redesign speed: the output is not linear PCM (Spotify's side %@, the hardware's %@)", clientRead ? @"is" : @"is not", hardwareRead ? @"is" : @"is not");
        if (!clientRead) return;
    }
    if (logged++ < 6) SGLog(@"redesign speed: Spotify's output is %.0f Hz, %u channels, %u bits, flags 0x%x, into the hardware's %.0f Hz, %u channels, %u bits, flags 0x%x, slices of %u, %@",
                            client.mSampleRate, (unsigned)client.mChannelsPerFrame, (unsigned)client.mBitsPerChannel, (unsigned)client.mFormatFlags,
                            hardware.mSampleRate, (unsigned)hardware.mChannelsPerFrame, (unsigned)hardware.mBitsPerChannel, (unsigned)hardware.mFormatFlags,
                            SGAudioPipelineMaximumFrames(), tapped() ? @"fed through the menu's unit" : @"not taken over");
}

static void apply(void);

static void prepareOutput(AudioUnit unit) {
    // The pipeline has excluded rendering while the graph changes. Do not run the previous
    // route's unit while the main queue prepares one for the newly reported format.
    atomic_store(&sg_engaged, false);
    readFormat(unit);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (sg_speed != 1 || sg_semitones != 0) apply();
    });
}

#pragma mark - engaging the unit

// Stops the render thread using a unit, and returns once it no longer is.
static void disengage(void) {
    atomic_store(&sg_engaged, false);
    for (int i = 0; i < 200 && atomic_load(&sg_busy); i++) usleep(250);
}

// The unit for the output's format and the way in use, made when there is none or the format changed. A
// replaced one is never freed: the render thread may still hold it, and a format change is rare.
static SGTimePitch *unitForFormat(void) {
    BOOL pull = tapped();
    Format *format = pull ? &sg_client : &sg_hardware;
    double rate;
    uint64_t bits = atomic_load(&format->rateBits);
    memcpy(&rate, &bits, sizeof rate);
    UInt32 channels = atomic_load(&format->channels);
    if (pull) {
        // In the chain the unit hands its buffers to the RemoteIO unit as they are: float, one per channel.
        UInt32 flags = atomic_load(&format->flags);
        BOOL canonical = (flags & kAudioFormatFlagIsFloat) && (flags & kAudioFormatFlagIsNonInterleaved) && atomic_load(&format->bytes) == 4;
        if (!canonical) {
            static int logged;
            if (logged++ < 3) SGLog(@"redesign speed: the output is not float per channel (flags 0x%x), speed cannot apply", (unsigned)flags);
            return NULL;
        }
    }
    if (rate <= 0 || channels < 1 || channels > kSGTimePitchMaxChannels) return NULL;
    _Atomic(SGTimePitch *) *slot = pull ? &sg_pull : &sg_inPlace;
    pthread_mutex_lock(&sg_buildLock);
    SGTimePitch *unit = atomic_load(slot);
    if (!unit || SGTimePitchSampleRate(unit) != rate || SGTimePitchChannels(unit) != channels) {
        BOOL wasEngaged = atomic_load(&sg_engaged);
        disengage();
        unit = SGTimePitchCreate(rate, channels, pull ? pullForUnit : NULL, NULL);
        if (unit) {
            SGTimePitchSetRate(unit, pull ? sg_speed : 1);
            SGTimePitchSetSemitones(unit, sg_semitones);
        }
        atomic_store(slot, unit);
        SGLog(@"redesign speed: %@ %@ for %.0f Hz, %u channels", unit ? @"a unit" : @"no unit", pull ? @"in the chain" : @"in place", rate, (unsigned)channels);
        if (unit && wasEngaged) atomic_store(&sg_engaged, true);
    }
    pthread_mutex_unlock(&sg_buildLock);
    return unit;
}

static void report(void) {
    SGTimePitch *unit = atomic_load(tapped() ? &sg_pull : &sg_inPlace);
    if (!unit) return;
    SGLog(@"redesign speed: %.2fx, %+.0f st, %u underruns, %u failures, largest pull %u, %.1f s of input", sg_speed, sg_semitones,
          SGTimePitchUnderruns(unit), SGTimePitchFailures(unit), SGTimePitchLargestPull(unit),
          SGTimePitchConsumed(unit) / SGTimePitchSampleRate(unit));
}

// Puts the unit in or takes it out for the current speed and pitch.
static void apply(void) {
    BOOL normal = sg_speed == 1 && sg_semitones == 0;
    static NSUInteger change;
    NSUInteger thisChange = ++change;
    if (normal) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kOffAfter * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (thisChange != change || sg_speed != 1 || sg_semitones != 0 || !atomic_load(&sg_engaged)) return;
            report();
            disengage();
        });
    }
    SGTimePitch *unit = unitForFormat();
    if (!unit) {
        static int logged;
        if (!normal && logged++ < 3) SGLog(@"redesign speed: Spotify's output has not started, nothing to change yet");
        return;
    }
    SGTimePitchSetRate(unit, tapped() ? sg_speed : 1);
    SGTimePitchSetSemitones(unit, sg_semitones);
    if (!normal && !atomic_load(&sg_engaged)) {
        disengage();
        SGTimePitchReset(unit);
        atomic_store(&sg_engaged, true);
    }
}

#pragma mark - the menu's calls

double SGPlayerAudioLatency(void) {
    SGTimePitch *unit = atomic_load(&sg_pull);
    return atomic_load(&sg_engaged) && unit ? SGTimePitchLatency(unit) : 0;
}

double SGPlayerSpeed(void) {
    return sg_speed;
}

BOOL SGPlayerSpeedAllowed(void) {
    return tapped();
}

void SGSetPlayerSpeed(double speed) {
    if (!tapped()) return;
    sg_speed = (float)speed;
    storeFloat(&sg_speedBits, sg_speed);
    apply();
}

float SGPlayerPitch(void) {
    return sg_semitones;
}

void SGSetPlayerPitch(float semitones) {
    if (!SGAudioPipelineAvailable() && !tapped()) return;
    sg_semitones = semitones;
    apply();
}

BOOL SGPlayerPitchAvailable(void) {
    return SGAudioPipelineAvailable() || tapped();
}

#pragma mark - Spotify's clock

%hook SPTPlayerState
- (double)playbackSpeed {
    double speed = %orig;
    float ours = loadFloat(&sg_speedBits);
    return ours > 0 && ours != 1 ? speed * ours : speed;
}
%end

%ctor {
    storeFloat(&sg_speedBits, 1);
    static const SGAudioProcessor processor = {prepareOutput, rendered};
    SGAudioPipelineRegister(SGAudioStageSpeedPitch, &processor);
    SGAudioPipelineSetPullProcessor(processPull);
    %init;
    SGRequireClasses(@[@"SPTPlayerState"]);
}
