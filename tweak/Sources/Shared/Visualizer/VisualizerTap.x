// The visualizer's tap (Visualizer.h): Audio/SGAudioPipeline's last stage, joined when a ring first shows, so what is read is what is heard.
// The render callback only folds the buffer to mono and copies it into SGSpectrum's ring, and only while
// a ring is on screen; the analysis runs on the main thread, once a frame, in SGVisualizerReadBars.
#import "Core/SGCore.h"
#import "Shared/Audio/SGAudioPipeline.h"
#import "Shared/Haptics/Haptics.h"
#import "SGSpectrum.h"
#import "Visualizer.h"
#include <stdatomic.h>

enum { kMonoChunk = 1024 };

static SGSpectrumRing sg_ring;
static atomic_bool sg_listening;
// The format the notify's buffers are in, packed as Music Haptics packs it: flags, then channels, then bytes.
static atomic_uint_fast64_t sg_layout, sg_rateBits;
static float sg_mono[kMonoChunk];

static SGSpectrumAnalyzer sg_analyzer;
static float sg_window[SGSpectrumWindow];
static NSInteger sg_count;
static double sg_rate;
static SGSpectrumFollows sg_follows;
static float sg_bassShare;

static inline float sampleAt(const void *data, UInt32 index, UInt32 bytes, BOOL isFloat, UInt32 fraction) {
    if (bytes == 4) {
        if (isFloat) return ((const float *)data)[index];
        int32_t value = ((const int32_t *)data)[index];
        return fraction ? (float)((double)value / (double)(1u << fraction)) : (float)(value / 2147483648.0);
    }
    return ((const int16_t *)data)[index] / 32768.0f;
}

static void readFormat(AudioUnit unit) {
    AudioStreamBasicDescription format = {0};
    UInt32 size = sizeof format;
    OSStatus status = AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &format, &size);
    UInt32 bytes = format.mBitsPerChannel / 8;
    BOOL takes = status == noErr && format.mFormatID == kAudioFormatLinearPCM && format.mSampleRate > 0 && format.mChannelsPerFrame >= 1
                 && (bytes == 2 || bytes == 4) && ((format.mFormatFlags & kAudioFormatFlagIsFloat) || (format.mFormatFlags & kAudioFormatFlagIsSignedInteger));
    if (!takes) {
        atomic_store(&sg_layout, 0);
        return;
    }
    double rate = format.mSampleRate;
    uint64_t bits;
    memcpy(&bits, &rate, sizeof bits);
    atomic_store(&sg_rateBits, bits);
    atomic_store(&sg_layout, (uint64_t)format.mFormatFlags | (uint64_t)(format.mChannelsPerFrame & 0xffff) << 32 | (uint64_t)bytes << 48);
}

static OSStatus rendered(void *refCon, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *timestamp, UInt32 bus,
                         UInt32 frames, AudioBufferList *data) {
    if (!atomic_load_explicit(&sg_listening, memory_order_relaxed)) return noErr;
    if (!(*flags & kAudioUnitRenderAction_PostRender) || bus != 0 || !data || !data->mNumberBuffers || !frames) return noErr;
    if (*flags & kAudioUnitRenderAction_OutputIsSilence) return noErr;
    uint64_t layout = atomic_load_explicit(&sg_layout, memory_order_relaxed);
    UInt32 formatFlags = (UInt32)layout, channels = (UInt32)(layout >> 32) & 0xffff, bytes = (UInt32)(layout >> 48);
    BOOL isFloat = (formatFlags & kAudioFormatFlagIsFloat) != 0;
    BOOL split = (formatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
    UInt32 fraction = (formatFlags & kLinearPCMFormatFlagsSampleFractionMask) >> kLinearPCMFormatFlagsSampleFractionShift;
    if ((bytes != 2 && bytes != 4) || channels < 1) return noErr;
    BOOL fits = split ? data->mNumberBuffers == channels : data->mNumberBuffers == 1 && data->mBuffers[0].mNumberChannels == channels;
    for (UInt32 b = 0; fits && b < data->mNumberBuffers; b++) {
        fits = data->mBuffers[b].mData && data->mBuffers[b].mDataByteSize == frames * bytes * (split ? 1 : channels);
    }
    if (!fits) return noErr;
    const void *left = data->mBuffers[0].mData, *right = split && channels > 1 ? data->mBuffers[1].mData : left;
    UInt32 stride = split ? 1 : channels, rightOffset = !split && channels > 1 ? 1 : 0;
    for (UInt32 done = 0; done < frames;) {
        UInt32 count = MIN(frames - done, (UInt32)kMonoChunk);
        for (UInt32 i = 0; i < count; i++) {
            UInt32 at = (done + i) * stride;
            sg_mono[i] = 0.5f * (sampleAt(left, at, bytes, isFloat, fraction) + sampleAt(right, at + rightOffset, bytes, isFloat, fraction));
        }
        SGSpectrumRingWrite(&sg_ring, sg_mono, count);
        done += count;
    }
    return noErr;
}

static void settingsChanged(void);

// The stage joins the pipeline the first time a ring shows, not at launch, so nobody without a ring on
// screen carries it: it once froze Spotify as a song started, for everyone, visualizer on or off. Joining
// late misses the prepare of the output already running, so its format is read here instead.
static void join(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        static const SGAudioProcessor processor = {readFormat, rendered};
        if (!SGAudioPipelineRegister(SGAudioStageVisualizer, &processor)) return;
        AudioUnit unit = SGAudioPipelineOutputUnit();
        if (unit) readFormat(unit);
        [NSNotificationCenter.defaultCenter addObserverForName:SGVisualizerSettingsDidChangeNotification object:nil
                                                         queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { settingsChanged(); }];
    });
}

// A ring on screen in the app, the lock screen's frames (LockScreenLyrics.x) or the Live Activity's player
// view (Shared/LiveActivity), any of them keeps it reading.
static BOOL sg_ringShows, sg_lockScreen, sg_liveActivity;
static void listen(void) {
    BOOL listening = sg_ringShows || sg_lockScreen || sg_liveActivity;
    if (listening && !SGOff("visualizer")) join();
    atomic_store(&sg_listening, listening);
}

void SGVisualizerSetListening(BOOL listening) {
    sg_ringShows = listening;
    listen();
}

void SGVisualizerSetLockScreenListening(BOOL listening) {
    sg_lockScreen = listening;
    listen();
}

void SGVisualizerSetLiveActivityListening(BOOL listening) {
    sg_liveActivity = listening;
    listen();
}

static double rate(void) {
    uint64_t bits = atomic_load(&sg_rateBits);
    double value;
    memcpy(&value, &bits, sizeof value);
    return value > 0 ? value : 44100;
}

// Its own settings, or Music Haptics' with the switch that takes them.
static float strength(void) {
    BOOL haptics = SGFlag(SGKeyVisualizerLikeHaptics, NO);
    NSInteger percent = SGInt(haptics ? SGKeyMusicStrength : SGKeyVisualizerStrength, 100);
    return (float)MAX(20, MIN(200, percent)) / 100;
}

static SGSpectrumFollows follows(void) {
    BOOL haptics = SGFlag(SGKeyVisualizerLikeHaptics, NO);
    NSInteger value = haptics ? SGMusicHapticsFollows() : SGInt(SGKeyVisualizerFollows, SGMusicFollowsEverything);
    switch (value) {
        case SGMusicFollowsBeat: return SGSpectrumBeat;
        case SGMusicFollowsBass: return SGSpectrumBass;
        default: return SGSpectrumEverything;
    }
}

static float sg_strength = 1;

BOOL SGVisualizerReadBars(float *bars, NSInteger count, float elapsed) {
    if (!bars || count <= 0) return NO;
    count = MIN(count, (NSInteger)SGSpectrumMaxBands);
    // Rings drawn in the same frame share one analysis: a second read would take the first's sound.
    static float lastBars[SGSpectrumMaxBands];
    static NSInteger lastCount;
    static CFTimeInterval lastAt;
    static BOOL lastHeard;
    CFTimeInterval at = CACurrentMediaTime();
    if (count == lastCount && at - lastAt < 0.004) {
        memcpy(bars, lastBars, sizeof(float) * count);
        return lastHeard;
    }
    // Another reader with another count read a moment ago (the lock screen's frames while the Live Activity
    // asks for its few): its bars, gathered into this many, rather than the analysis started over for each.
    if (lastCount > 0 && count != lastCount && at - lastAt < 0.3) {
        for (NSInteger b = 0; b < count; b++) {
            NSInteger from = b * lastCount / count, to = MAX(from + 1, (b + 1) * lastCount / count);
            float most = 0;
            for (NSInteger i = from; i < to && i < lastCount; i++) most = MAX(most, lastBars[i]);
            bars[b] = most;
        }
        return lastHeard;
    }
    // Music Haptics' strength and what it follows can change on their own page; read again now and then.
    static CFTimeInterval settingsAt;
    if (at - settingsAt > 1) {
        settingsAt = at;
        settingsChanged();
    }
    double now = rate();
    if (count != sg_count || now != sg_rate) {
        sg_follows = follows();
        sg_strength = strength();
        sg_bassShare = SGVisualizerBassShare();
        float rise, fall;
        SGVisualizerResponse(&rise, &fall);
        SGSpectrumSetResponse(&sg_analyzer, rise, fall);
        SGSpectrumResetShaped(&sg_analyzer, (int)count, now, sg_follows, sg_bassShare);
        sg_count = count;
        sg_rate = now;
    }
    BOOL heard = SGSpectrumRingRead(&sg_ring, sg_window) && SGAudioPipelineTapped();
    if (heard) SGSpectrumProcess(&sg_analyzer, sg_window, elapsed, sg_strength, bars);
    else SGSpectrumDecay(&sg_analyzer, elapsed, bars);
    memcpy(lastBars, bars, sizeof(float) * count);
    lastCount = count;
    lastAt = at;
    lastHeard = heard;
    return heard;
}

static void settingsChanged(void) {
    // Read once here rather than every frame; a change of what is followed, or of the bass's share of the
    // ring, starts the bars over. How they move applies from the next frame.
    sg_strength = strength();
    SGSpectrumFollows now = follows();
    if (now != sg_follows || SGVisualizerBassShare() != sg_bassShare) sg_count = 0;
    float rise, fall;
    SGVisualizerResponse(&rise, &fall);
    SGSpectrumSetResponse(&sg_analyzer, rise, fall);
}
