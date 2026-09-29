// Runs the audio effects' engine (tweak/Sources/Shared/AudioEffects) on the Mac the way the tweak runs it: a
// song decoded with ExtAudioFile, and test signals, go through the engine in slices of the sizes iOS hands its
// output unit (1024, 4096, 470 and 471 in turn, 512, and a mix down to single frames). Each check prints a line.
//
// - bypass: every effect off, the output is the input one block later, sample for sample, at any level;
// - output gain, and the limiter's ceiling with the gain far over it;
// - the equalizer's bands at their gains, measured with a stepped sine sweep; bass boost, lifting quiet lows
//   and holding back loud ones;
// - the Graphic EQ's FIR against its curve; the convolver: Dirac responses as identity, a random 4 path
//   response against direct convolution, resampling, the modes, the files it refuses;
// - ViPER DDC files in either feedback sign, at their rates and moved to another; Liveprog scripts, their
//   errors with the file's lines, memory without allocation;
// - reverb tails by preset, stereo widening, crossfeed keeping mono mono, the tube's harmonics and aliases,
//   the compander flat at zero and evening out or widening dynamics;
// - crossfades without clicks, everything on (finite, under the ceiling, no allocation on the render thread,
//   by malloc_logger, so Apple's reverb unit is counted too), a sample rate change, a reset, a thread changing
//   settings while another processes, and what each effect costs per 1024-frame block.
//
//     ./build.sh && build/audio-effects <song> <out dir>
//     ./build.sh thread && build/audio-effects-thread <song> <out dir> stress     (and address)
#import <Foundation/Foundation.h>
#import <Accelerate/Accelerate.h>
#import <AudioToolbox/AudioToolbox.h>
#import <mach/mach_time.h>
#import <pthread.h>
#import <stdatomic.h>
#import "Shared/AudioEffects/SGDSPConvolver.h"
#import "Shared/AudioEffects/SGDSPEffects.h"
#import "Shared/AudioEffects/SGDSPEngine.h"
#import "Shared/AudioEffects/SGDSPFilters.h"

static const double kRate = 48000;
static int sg_failures;
static NSString *sg_outDir;

#define CHECK(ok, ...) do { bool _ok = (ok); if (!_ok) sg_failures++; printf("%s ", _ok ? "  ok  " : "FAILED"); printf(__VA_ARGS__); printf("\n"); } while (0)

static const double kEqFrequencies[15] = {25, 40, 63, 100, 160, 250, 400, 630, 1000, 1600, 2500, 4000, 6300, 10000, 16000};
static const double kCompanderFrequencies[7] = {95, 200, 400, 800, 1600, 3400, 7500};

#pragma mark - allocations and frees on the render thread

typedef void(malloc_logger_t)(uint32_t type, uintptr_t arg1, uintptr_t arg2, uintptr_t arg3, uintptr_t result, uint32_t skip);
extern malloc_logger_t *malloc_logger;

static pthread_t sg_renderThread;
static atomic_bool sg_inRender;
static atomic_uint sg_renderAllocations;

__attribute__((unused)) static void countAllocation(uint32_t type, uintptr_t a, uintptr_t b, uintptr_t c, uintptr_t result, uint32_t skip) {
    if (atomic_load_explicit(&sg_inRender, memory_order_relaxed) && pthread_equal(pthread_self(), sg_renderThread)) {
        atomic_fetch_add_explicit(&sg_renderAllocations, 1, memory_order_relaxed);
    }
}

#if !__has_feature(address_sanitizer) && !__has_feature(thread_sanitizer)
#define SG_COUNTS_ALLOCATIONS 1
#endif

#pragma mark - audio

typedef struct {
    float *left, *right;
    size_t frames;
} Audio;

static Audio makeAudio(size_t frames) {
    return (Audio){calloc(frames, sizeof(float)), calloc(frames, sizeof(float)), frames};
}

static Audio copyAudio(Audio audio) {
    Audio copy = makeAudio(audio.frames);
    memcpy(copy.left, audio.left, audio.frames * sizeof(float));
    memcpy(copy.right, audio.right, audio.frames * sizeof(float));
    return copy;
}

static void freeAudio(Audio audio) {
    free(audio.left);
    free(audio.right);
}

static void scaleAudio(Audio audio, float gain) {
    vDSP_vsmul(audio.left, 1, &gain, audio.left, 1, audio.frames);
    vDSP_vsmul(audio.right, 1, &gain, audio.right, 1, audio.frames);
}

static AudioStreamBasicDescription floatFormat(double rate, UInt32 channels, bool interleaved) {
    return (AudioStreamBasicDescription){
        .mSampleRate = rate, .mFormatID = kAudioFormatLinearPCM,
        .mFormatFlags = kAudioFormatFlagsNativeFloatPacked | (interleaved ? 0 : kAudioFormatFlagIsNonInterleaved),
        .mBytesPerPacket = interleaved ? 4 * channels : 4, .mFramesPerPacket = 1, .mBytesPerFrame = interleaved ? 4 * channels : 4,
        .mChannelsPerFrame = channels, .mBitsPerChannel = 32,
    };
}

static Audio decode(NSString *path, double rate, double seconds) {
    ExtAudioFileRef file;
    if (ExtAudioFileOpenURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], &file)) {
        printf("cannot open %s\n", path.UTF8String);
        exit(1);
    }
    AudioStreamBasicDescription format = floatFormat(rate, 2, false);
    ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat, sizeof format, &format);
    Audio audio = makeAudio((size_t)(rate * seconds));
    size_t done = 0;
    while (done < audio.frames) {
        UInt32 frames = (UInt32)MIN((size_t)8192, audio.frames - done);
        struct { AudioBufferList list; AudioBuffer second; } buffers = {{2, {{1, frames * 4, audio.left + done}}}, {1, frames * 4, audio.right + done}};
        if (ExtAudioFileRead(file, &frames, &buffers.list) || !frames) break;
        done += frames;
    }
    ExtAudioFileDispose(file);
    audio.frames = done;
    return audio;
}

// Interleaved float samples of `channels` into a file of `type` (WAV float or 16-bit, or FLAC).
static bool writeFile(NSString *path, AudioFileTypeID type, const float *interleaved, UInt32 channels, size_t frames, double rate, int bits) {
    AudioStreamBasicDescription stored = {.mSampleRate = rate, .mChannelsPerFrame = channels};
    if (type == kAudioFileFLACType) {
        stored.mFormatID = kAudioFormatFLAC;
        stored.mFormatFlags = kAppleLosslessFormatFlag_24BitSourceData;
        stored.mFramesPerPacket = 4096;
    } else if (bits == 32) {
        stored = floatFormat(rate, channels, true);
    } else {
        stored.mFormatID = kAudioFormatLinearPCM;
        stored.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
        stored.mBitsPerChannel = 16;
        stored.mBytesPerFrame = stored.mBytesPerPacket = 2 * channels;
        stored.mFramesPerPacket = 1;
    }
    ExtAudioFileRef file;
    if (ExtAudioFileCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], type, &stored, NULL, kAudioFileFlags_EraseFile, &file)) return false;
    AudioStreamBasicDescription client = floatFormat(rate, channels, true);
    bool ok = !ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat, sizeof client, &client);
    AudioBufferList list = {1, {{channels, (UInt32)(frames * 4 * channels), (void *)interleaved}}};
    ok = ok && !ExtAudioFileWrite(file, (UInt32)frames, &list);
    ExtAudioFileDispose(file);
    return ok;
}

static void writeSong(NSString *name, Audio audio) {
    float *interleaved = malloc(audio.frames * 2 * sizeof(float));
    vDSP_ztoc(&(DSPSplitComplex){audio.left, audio.right}, 1, (DSPComplex *)interleaved, 2, audio.frames);
    writeFile([sg_outDir stringByAppendingPathComponent:name], kAudioFileWAVEType, interleaved, 2, audio.frames, kRate, 16);
    free(interleaved);
}

#pragma mark - running the engine

enum { kPattern1024, kPattern4096, kPatternOdd, kPattern512, kPatternMixed, kPatternCount };
static const char *kPatternNames[] = {"1024", "4096", "470/471", "512", "mixed"};

static uint32_t sliceAt(int pattern, size_t index) {
    static const uint32_t mixed[] = {1024, 4096, 470, 471, 512, 941, 1, 2048, 1023, 1025};
    switch (pattern) {
    case kPattern1024: return 1024;
    case kPattern4096: return 4096;
    case kPatternOdd: return index % 2 ? 471 : 470;
    case kPattern512: return 512;
    default: return mixed[index % 10];
    }
}

typedef struct {
    double meanMS, peakMS;
    uint64_t calls;
} Timing;

static double ticksToMS(uint64_t ticks) {
    static mach_timebase_info_data_t timebase;
    if (!timebase.denom) mach_timebase_info(&timebase);
    return ticks * (double)timebase.numer / timebase.denom / 1e6;
}

// The audio processed in place through the engine, a slice at a time, as the notify does.
static Timing run(SGDSPEngine *engine, Audio audio, int pattern) {
    Timing timing = {0};
    uint64_t total = 0, peak = 0;
    size_t index = 0;
    sg_renderThread = pthread_self();
    for (size_t done = 0; done < audio.frames;) {
        uint32_t frames = (uint32_t)MIN((size_t)sliceAt(pattern, index++), audio.frames - done);
        uint64_t start = mach_absolute_time();
        atomic_store_explicit(&sg_inRender, true, memory_order_relaxed);
        SGDSPEngineProcess(engine, audio.left + done, audio.right + done, frames);
        atomic_store_explicit(&sg_inRender, false, memory_order_relaxed);
        uint64_t ticks = mach_absolute_time() - start;
        total += ticks;
        if (ticks > peak) peak = ticks;
        done += frames;
        timing.calls++;
    }
    timing.meanMS = ticksToMS(total) / timing.calls;
    timing.peakMS = ticksToMS(peak);
    return timing;
}

// Samples that differ from the input one block earlier, and the largest difference.
static size_t delayedDifferences(Audio input, Audio output, float *largest) {
    size_t differ = 0;
    *largest = 0;
    for (size_t i = 0; i < output.frames; i++) {
        float wantLeft = i < kSGDSPEngineBlock ? 0 : input.left[i - kSGDSPEngineBlock];
        float wantRight = i < kSGDSPEngineBlock ? 0 : input.right[i - kSGDSPEngineBlock];
        if (memcmp(&output.left[i], &wantLeft, 4) || memcmp(&output.right[i], &wantRight, 4)) differ++;
        *largest = fmaxf(*largest, fmaxf(fabsf(output.left[i] - wantLeft), fabsf(output.right[i] - wantRight)));
    }
    return differ;
}

static bool finiteAndBounded(Audio audio, float bound, float *peak) {
    *peak = 0;
    for (size_t i = 0; i < audio.frames; i++) {
        if (!isfinite(audio.left[i]) || !isfinite(audio.right[i])) return false;
        *peak = fmaxf(*peak, fmaxf(fabsf(audio.left[i]), fabsf(audio.right[i])));
    }
    return *peak <= bound;
}

static void allOff(SGDSPEngine *engine) {
    char error[300];
    double zeros[15] = {0};
    SGDSPEngineSetOutput(engine, 0, -0.1, 60);
    SGDSPEngineSetCompander(engine, false, 0.22, kCompanderFrequencies, zeros);
    SGDSPEngineSetBassBoost(engine, false, 5);
    SGDSPEngineSetEqualizer(engine, false, kEqFrequencies, zeros);
    SGDSPEngineSetGraphicEq(engine, false, NULL, error, sizeof error);
    SGDSPEngineSetConvolver(engine, false, NULL, 0, error, sizeof error);
    SGDSPEngineSetDDC(engine, false, NULL, error, sizeof error);
    SGDSPEngineSetLiveprog(engine, false, NULL, error, sizeof error);
    SGDSPEngineSetReverb(engine, false, 5);
    SGDSPEngineSetStereoWide(engine, false, 60);
    SGDSPEngineSetCrossfeed(engine, false, 2);
    SGDSPEngineSetTube(engine, false, 2);
}

#pragma mark - measuring

// A tone's amplitude by a Hann-windowed DFT at its frequency.
static double toneLevel(const float *samples, size_t count, double frequency, double rate) {
    double re = 0, im = 0, window = 0;
    for (size_t i = 0; i < count; i++) {
        double w = 0.5 - 0.5 * cos(2 * M_PI * i / (count - 1));
        double phase = 2 * M_PI * frequency * i / rate;
        re += samples[i] * w * cos(phase);
        im += samples[i] * w * sin(phase);
        window += w;
    }
    return 20 * log10(2 * hypot(re, im) / window + 1e-30);
}

static Audio tone(double frequency, double amplitude, double seconds, double rate, bool leftOnly) {
    Audio audio = makeAudio((size_t)(seconds * rate));
    for (size_t i = 0; i < audio.frames; i++) {
        audio.left[i] = (float)(amplitude * sin(2 * M_PI * frequency * i / rate));
        audio.right[i] = leftOnly ? 0 : audio.left[i];
    }
    return audio;
}

// A stepped sine: the tone for a second through the engine, its level over the last half second against the input's, in dB.
static double stepGain(SGDSPEngine *engine, double frequency, double amplitude, double rate, double *right) {
    Audio audio = tone(frequency, amplitude, 1, rate, false);
    run(engine, audio, kPatternOdd);
    size_t from = audio.frames / 2, count = audio.frames - from;
    double input = 20 * log10(amplitude);
    double left = toneLevel(audio.left + from, count, frequency, rate) - input;
    if (right) *right = toneLevel(audio.right + from, count, frequency, rate) - input;
    freeAudio(audio);
    return left;
}

// The time an impulse's energy takes to fall 30 dB under its peak (a fifth-of-a-second smoothing), doubled.
static double reverberationTime(const float *samples, size_t count, double rate) {
    size_t window = (size_t)(0.05 * rate);
    double peak = 0, at = 0;
    for (size_t start = 0; start + window < count; start += window / 2) {
        float energy = 0;
        vDSP_svesq(samples + start, 1, &energy, window);
        if (energy > peak) {
            peak = energy;
            at = start;
        }
    }
    double last = at;
    for (size_t start = (size_t)at; start + window < count; start += window / 2) {
        float energy = 0;
        vDSP_svesq(samples + start, 1, &energy, window);
        if (energy > peak * 1e-3) last = start;
    }
    return 2 * (last - at) / rate;
}

#pragma mark - bypass and output

static void checkBypass(Audio song) {
    printf("\nbypass: every effect off, the output is the input one block later\n");
    for (int pattern = 0; pattern < kPatternCount; pattern++) {
        SGDSPEngine *engine = SGDSPEngineCreate(kRate);
        allOff(engine);
        // Hotter than full scale too: float output from Spotify is not clipped.
        Audio hot = copyAudio(song);
        scaleAudio(hot, 1.5f);
        Audio output = copyAudio(hot);
        run(engine, output, pattern);
        float largest;
        size_t differ = delayedDifferences(hot, output, &largest);
        CHECK(differ == 0, "slices of %-8s at +3.5 dBFS: %zu of %zu samples differ from the input 1024 frames earlier", kPatternNames[pattern], differ,
              output.frames * 2);
        freeAudio(output);
        freeAudio(hot);
        SGDSPEngineFree(engine);
    }
    // Effects switched on and back off leave it exact again once their fades are done.
    SGDSPEngine *engine = SGDSPEngineCreate(kRate);
    allOff(engine);
    char error[300];
    SGDSPEngineSetEqualizer(engine, true, kEqFrequencies, (double[15]){3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, -3});
    SGDSPEngineSetLiveprog(engine, true, "@sample\nspl0 = spl1;\n", error, sizeof error);
    Audio warm = copyAudio(song);
    warm.frames = (size_t)kRate * 2;
    run(engine, warm, kPatternMixed);
    allOff(engine);
    Audio quiet = copyAudio(song);
    quiet.frames = (size_t)kRate * 4;
    Audio out = copyAudio(quiet);
    run(engine, out, kPatternMixed);
    size_t exact = 0;
    for (size_t i = kSGDSPEngineBlock * 3; i < out.frames; i++) exact += out.left[i] == quiet.left[i - kSGDSPEngineBlock] && out.right[i] == quiet.right[i - kSGDSPEngineBlock];
    CHECK(exact == out.frames - kSGDSPEngineBlock * 3, "effects switched off: exact again two blocks later (%zu of %zu samples)", exact, out.frames - kSGDSPEngineBlock * 3);
    freeAudio(warm);
    freeAudio(quiet);
    freeAudio(out);
    SGDSPEngineFree(engine);
}

static void checkRestart(Audio song) {
    SGDSPEngine *engine = SGDSPEngineCreate(kRate);
    allOff(engine);
    Audio quiet = copyAudio(song);
    quiet.frames = (size_t)kRate * 4;
    Audio first = copyAudio(quiet);
    run(engine, first, kPatternOdd);
    SGDSPEngineRestart(engine);
    Audio second = copyAudio(quiet);
    run(engine, second, kPatternOdd);
    float largest;
    size_t differ = delayedDifferences(quiet, second, &largest);
    CHECK(differ == 0, "after a restart the stream starts over one block late (%zu samples differ)", differ);
    freeAudio(first);
    freeAudio(second);
    freeAudio(quiet);
    SGDSPEngineFree(engine);
}

static void checkOutput(Audio song) {
    printf("\noutput gain and limiter\n");
    SGDSPEngine *engine = SGDSPEngineCreate(kRate);
    allOff(engine);
    SGDSPEngineSetOutput(engine, -6, -0.1, 60);
    double gain = stepGain(engine, 1000, 0.5, kRate, NULL);
    CHECK(fabs(gain + 6) < 0.01, "post gain -6 dB: a 1 kHz tone comes out %+.3f dB", gain);
    const double thresholds[] = {-0.1, -6, -20};
    for (int t = 0; t < 3; t++) {
        SGDSPEngineSetOutput(engine, 12, thresholds[t], 60);
        SGDSPEngineRestart(engine);
        Audio loud = copyAudio(song);
        loud.frames = (size_t)kRate * 20;
        run(engine, loud, kPatternMixed);
        float peak = 0, ceiling = (float)pow(10, thresholds[t] / 20);
        bool fine = finiteAndBounded(loud, ceiling * 1.000001f, &peak);
        CHECK(fine, "+12 dB into a limiter at %.1f dB: the song peaks at %.3f dBFS", thresholds[t], 20 * log10(peak));
        if (t == 0) writeSong(@"limiter-12dB.wav", loud);
        freeAudio(loud);
    }
    // Release: after a burst the gain comes back up at the release's pace.
    SGDSPEngineSetOutput(engine, 0, -12, 100);
    SGDSPEngineRestart(engine);
    Audio burst = makeAudio((size_t)kRate * 2);
    for (size_t i = 0; i < burst.frames; i++) burst.left[i] = burst.right[i] = (float)((i < kRate / 2 ? 0.9 : 0.1) * sin(2 * M_PI * 1000 * i / kRate));
    run(engine, burst, kPattern1024);
    size_t after = (size_t)(kRate / 2) + kSGDSPEngineBlock;
    double early = toneLevel(burst.left + after + 480, 960, 1000, kRate), late = toneLevel(burst.left + after + (size_t)kRate, 4800, 1000, kRate);
    CHECK(early < late - 3 && fabs(late + 20) < 0.1, "release 100 ms: 10 ms after a burst a quiet tone is %.1f dB, a second later %.2f dB (as it went in: -20.00)",
          early, late);
    freeAudio(burst);
    SGDSPEngineFree(engine);
}

#pragma mark - equalizer and bass

static void checkEqualizer(void) {
    printf("\nthe equalizer, a stepped sine at each band\n");
    SGDSPEngine *engine = SGDSPEngineCreate(kRate);
    allOff(engine);
    SGDSPEngineSetOutput(engine, -24, -0.1, 60);
    const struct { const char *name; double gains[15]; } settings[] = {
        {"a smile", {6, 5, 4, 2, 1, 0, -1, -2, -1, 0, 1, 2, 4, 5, 6}},
        {"all +12", {12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12}},
        {"alternating", {12, -12, 12, -12, 12, -12, 12, -12, 12, -12, 12, -12, 12, -12, 12}},
        {"one band", {0, 0, 0, 0, 0, 0, 0, 9, 0, 0, 0, 0, 0, 0, 0}},
        {"random", {-3.2, 7.1, 0.4, -8.8, 2.5, 11.0, -1.3, 4.4, -6.6, 0.0, 3.3, -10.1, 5.5, -2.2, 8.0}},
    };
    for (size_t s = 0; s < sizeof settings / sizeof *settings; s++) {
        SGDSPEngineSetEqualizer(engine, true, kEqFrequencies, settings[s].gains);
        double worst = 0;
        char line[400] = "";
        for (int b = 0; b < 15; b++) {
            double gain = stepGain(engine, kEqFrequencies[b], 0.25, kRate, NULL) + 24;
            worst = fmax(worst, fabs(gain - settings[s].gains[b]));
            snprintf(line + strlen(line), sizeof line - strlen(line), " %+.1f", gain);
        }
        CHECK(worst <= 0.5, "%-11s each band within %.2f dB of its gain; measured%s", settings[s].name, worst, line);
    }
    // Between the bands the sound follows the curve the page draws.
    double frequencies[48], curve[48], worst = 0;
    SGDSPEngineEqualizerCurve(kEqFrequencies, settings[4].gains, 48, frequencies, curve);
    SGDSPEngineSetEqualizer(engine, true, kEqFrequencies, settings[4].gains);
    for (int i = 0; i < 48; i++) worst = fmax(worst, fabs(stepGain(engine, frequencies[i], 0.25, kRate, NULL) + 24 - curve[i]));
    CHECK(worst < 0.05, "at 48 points from 20 Hz to 20 kHz the sound is the page's curve within %.3f dB", worst);
    SGDSPEngineFree(engine);

    engine = SGDSPEngineCreate(44100);
    allOff(engine);
    SGDSPEngineSetOutput(engine, -24, -0.1, 60);
    SGDSPEngineSetEqualizer(engine, true, kEqFrequencies, settings[4].gains);
    worst = 0;
    for (int b = 0; b < 15; b++) worst = fmax(worst, fabs(stepGain(engine, kEqFrequencies[b], 0.25, 44100, NULL) + 24 - settings[4].gains[b]));
    CHECK(worst <= 0.5, "at 44.1 kHz too, 16 kHz band and all: within %.2f dB", worst);
    SGDSPEngineFree(engine);
}

static void checkBass(void) {
    printf("\nbass boost\n");
    SGDSPEngine *engine = SGDSPEngineCreate(kRate);
    allOff(engine);
    SGBiquad shelf = SGBiquadLowShelf(kRate, 100, M_SQRT1_2, 10);
    SGDSPEngineSetBassBoost(engine, true, 10);
    double low = stepGain(engine, 40, pow(10, -30 / 20.0), kRate, NULL), high = stepGain(engine, 5000, pow(10, -30 / 20.0), kRate, NULL);
    double want = SGBiquadGainDB(&shelf, 1, kRate, 40);
    CHECK(fabs(low - want) < 0.2 && fabs(high) < 0.05, "10 dB, quiet: 40 Hz at -30 dBFS %+.2f dB (the full shelf gives %+.2f), 5 kHz %+.2f dB", low, want, high);
    Audio loud = tone(40, pow(10, -6 / 20.0), 2, kRate, false);
    run(engine, loud, kPattern1024);
    float peak = 0;
    vDSP_maxmgv(loud.left + loud.frames / 2, 1, &peak, loud.frames / 2);
    CHECK(20 * log10(peak) < -2.5, "10 dB, a 40 Hz tone at -6 dBFS: lifted only to %.2f dBFS peak (the knee is -3)", 20 * log10(peak));
    freeAudio(loud);
    SGDSPEngineFree(engine);
}

#pragma mark - Graphic EQ and convolver

static void checkGraphicEq(void) {
    printf("\nGraphic EQ\n");
    SGDSPEngine *engine = SGDSPEngineCreate(kRate);
    allOff(engine);
    SGDSPEngineSetOutput(engine, -12, -0.1, 60);
    const char *text = "GraphicEQ: 20 6; 40 5; 80 3; 150 0; 400 -2; 1000 0; 2500 4; 4000 3; 7000 -4; 10000 -1; 16000 2; 20000 -6";
    char error[300] = "";
    bool ok = SGDSPEngineSetGraphicEq(engine, true, text, error, sizeof error);
    SGDSPGraphicCurve curve;
    SGDSPParseGraphicEq(text, &curve);
    double worst = 0, worstAt = 0;
    for (int i = 0; i < 40; i++) {
        double f = 40 * pow(16000 / 40.0, i / 39.0);
        double miss = fabs(stepGain(engine, f, 0.25, kRate, NULL) + 12 - SGDSPGraphicEqAt(&curve, f));
        if (miss > worst) {
            worst = miss;
            worstAt = f;
        }
    }
    SGDSPFreeGraphicEq(&curve);
    CHECK(ok && worst <= 0.5, "a 12 point curve, 40 Hz to 16 kHz at 40 frequencies: within %.2f dB of it (the most at %.0f Hz)", worst, worstAt);
    ok = SGDSPEngineSetGraphicEq(engine, true, "GraphicEQ: 20 -1; 30", error, sizeof error);
    CHECK(ok, "a GraphicEQ with an odd count of numbers loads its whole pairs");
    ok = SGDSPEngineSetGraphicEq(engine, true, "20 -1; 30 2", error, sizeof error);
    CHECK(!ok, "text without \"GraphicEQ:\" is refused: \"%s\"", error);
    SGDSPEngineFree(engine);
}

static NSString *irPath(NSString *name) {
    return [sg_outDir stringByAppendingPathComponent:name];
}

// Paths of `frames`, interleaved, written as a file.
static void writeImpulse(NSString *name, AudioFileTypeID type, float *const *paths, int count, size_t frames, double rate, int bits) {
    float *interleaved = malloc(frames * count * sizeof(float));
    for (size_t i = 0; i < frames; i++) {
        for (int p = 0; p < count; p++) interleaved[i * count + p] = paths[p][i];
    }
    if (!writeFile(irPath(name), type, interleaved, count, frames, rate, bits)) printf("         could not write %s\n", name.UTF8String);
    free(interleaved);
}

static double errorDB(const float *output, const float *reference, size_t count) {
    double error = 0, energy = 0;
    for (size_t i = 0; i < count; i++) {
        error += (double)(output[i] - reference[i]) * (output[i] - reference[i]);
        energy += (double)reference[i] * reference[i];
    }
    return 10 * log10(error / energy + 1e-30);
}

static void checkConvolver(Audio song) {
    printf("\nconvolver\n");
    char error[300] = "";
    SGDSPEngine *engine = SGDSPEngineCreate(kRate);
    allOff(engine);
    SGDSPEngineSetOutput(engine, -6, -0.1, 60);

    // Dirac responses of 1, 2 and 4 paths: the sound as it went in.
    float *dirac[4];
    for (int p = 0; p < 4; p++) dirac[p] = calloc(64, sizeof(float));
    dirac[0][0] = dirac[3][0] = 1;
    float *diracStereo[2] = {dirac[0], dirac[3]};
    writeImpulse(@"dirac-mono.wav", kAudioFileWAVEType, dirac, 1, 64, kRate, 32);
    writeImpulse(@"dirac-stereo.wav", kAudioFileWAVEType, diracStereo, 2, 64, kRate, 32);
    writeImpulse(@"dirac-4.wav", kAudioFileWAVEType, dirac, 4, 64, kRate, 32);
    const char *names[] = {"dirac-mono.wav", "dirac-stereo.wav", "dirac-4.wav"};
    Audio input = copyAudio(song);
    input.frames = (size_t)kRate * 5;
    scaleAudio(input, 0.5f);
    SGDSPEngineSetOutput(engine, 0, -0.1, 60);
    for (int n = 0; n < 3; n++) {
        bool ok = SGDSPEngineSetConvolver(engine, true, irPath(@(names[n])).UTF8String, 0, error, sizeof error);
        SGDSPEngineRestart(engine);
        Audio out = copyAudio(input);
        run(engine, out, kPatternMixed);
        size_t from = kSGDSPEngineBlock * 4;
        double left = errorDB(out.left + from, input.left + from - kSGDSPEngineBlock, out.frames - from);
        double right = errorDB(out.right + from, input.right + from - kSGDSPEngineBlock, out.frames - from);
        CHECK(ok && left < -100 && right < -100, "%-17s the song comes out as it went in, one block late: error %.0f and %.0f dB under it", names[n], left, right);
        freeAudio(out);
    }
    freeAudio(input);

    // A random 4 path response longer than the head, against direct convolution.
    size_t length = 50000;
    float *random[4];
    srand(7);
    for (int p = 0; p < 4; p++) {
        random[p] = malloc(length * sizeof(float));
        for (size_t i = 0; i < length; i++) random[p][i] = (float)((rand() / (double)RAND_MAX - 0.5) * exp(-3.0 * i / length));
    }
    writeImpulse(@"random-4.wav", kAudioFileWAVEType, random, 4, length, kRate, 32);
    double power[2] = {0, 0};
    for (int p = 0; p < 4; p++) {
        float sum = 0;
        vDSP_svesq(random[p], 1, &sum, length);
        power[p & 1] += sum;
    }
    float scale = (float)(1 / sqrt(fmax(power[0], power[1])));
    uint64_t start = mach_absolute_time();
    bool ok = SGDSPEngineSetConvolver(engine, true, irPath(@"random-4.wav").UTF8String, 0, error, sizeof error);
    double loadMS = ticksToMS(mach_absolute_time() - start);
    Audio noise = makeAudio((size_t)kRate * 3);
    for (size_t i = 0; i < noise.frames; i++) {
        noise.left[i] = (float)(rand() / (double)RAND_MAX - 0.5) * 0.1f;
        noise.right[i] = (float)(rand() / (double)RAND_MAX - 0.5) * 0.1f;
    }
    SGDSPEngineReset(engine);
    ok = ok && SGDSPEngineSetConvolver(engine, true, irPath(@"random-4.wav").UTF8String, 0, error, sizeof error);
    // The crossfade in takes the first block; the reference starts from there.
    SGDSPEngineRestart(engine);
    Audio silence = makeAudio(kSGDSPEngineBlock);
    run(engine, silence, kPattern1024);
    freeAudio(silence);
    Audio out = copyAudio(noise);
    run(engine, out, kPatternMixed);
    size_t padded = noise.frames + length - 1;
    float *reference[2] = {calloc(noise.frames, 4), calloc(noise.frames, 4)}, *in = calloc(padded, 4), *part = malloc(noise.frames * 4);
    for (int p = 0; p < 4; p++) {
        memset(in, 0, padded * 4);
        memcpy(in + length - 1, p < 2 ? noise.left : noise.right, noise.frames * 4);
        vDSP_conv(in, 1, random[p] + length - 1, -1, part, 1, noise.frames, length);
        vDSP_vsma(part, 1, &scale, reference[p & 1], 1, reference[p & 1], 1, noise.frames);
    }
    size_t compared = noise.frames - kSGDSPEngineBlock;
    double left = errorDB(out.left + kSGDSPEngineBlock, reference[0], compared), right = errorDB(out.right + kSGDSPEngineBlock, reference[1], compared);
    CHECK(ok && left < -100 && right < -100, "a random 4 path response of %zu frames (read and set up in %.0f ms): error %.0f and %.0f dB under direct convolution",
          length, loadMS, left, right);
    free(reference[0]);
    free(reference[1]);
    free(in);
    free(part);
    freeAudio(out);
    freeAudio(noise);

    // A Dirac at 44.1 kHz, resampled: flat to 20 kHz. Its power spread over 22.05 of 24 kHz, the scaling to
    // unit power lifts it by 0.37 dB. It sits 100 frames in, so the resampler's ringing before it is kept.
    float *centred = calloc(1024, sizeof(float));
    centred[100] = 1;
    writeImpulse(@"dirac-44k.wav", kAudioFileWAVEType, &centred, 1, 1024, 44100, 32);
    free(centred);
    ok = SGDSPEngineSetConvolver(engine, true, irPath(@"dirac-44k.wav").UTF8String, 0, error, sizeof error);
    double lowest = 100, highest = -100;
    for (int i = 0; i < 12; i++) {
        double gain = stepGain(engine, 50 * pow(400, i / 11.0), 0.25, kRate, NULL);
        lowest = fmin(lowest, gain);
        highest = fmax(highest, gain);
    }
    CHECK(ok && highest - lowest < 0.1, "a Dirac recorded at 44.1 kHz, resampled to 48: from 50 Hz to 20 kHz between %+.3f and %+.3f dB", lowest, highest);

    // The modes: a response 500 frames late and trailing silence.
    float *late = calloc(20000, sizeof(float));
    late[500] = 1;
    writeImpulse(@"late.wav", kAudioFileWAVEType, &late, 1, 20000, kRate, 32);
    SGDSPImpulse impulse;
    SGDSPReadImpulse(irPath(@"late.wav").UTF8String, kRate, SGDSPImpulseOriginal, &impulse, error, sizeof error);
    size_t original = impulse.length;
    SGDSPFreeImpulse(&impulse);
    SGDSPReadImpulse(irPath(@"late.wav").UTF8String, kRate, SGDSPImpulseTrimmed, &impulse, error, sizeof error);
    size_t trimmed = impulse.length;
    SGDSPFreeImpulse(&impulse);
    SGDSPReadImpulse(irPath(@"late.wav").UTF8String, kRate, SGDSPImpulseMinimumPhase, &impulse, error, sizeof error);
    size_t peakAt = 0;
    float peakValue = 0;
    for (size_t i = 0; i < impulse.length; i++) {
        if (fabsf(impulse.responses[0][i]) > peakValue) {
            peakValue = fabsf(impulse.responses[0][i]);
            peakAt = i;
        }
    }
    CHECK(original == 20000 && trimmed == 501 && peakAt == 0 && impulse.length < 16, "modes: original %zu frames, trimmed %zu, minimum phase %zu with its peak at %zu (was 500)",
          original, trimmed, impulse.length, peakAt);
    SGDSPFreeImpulse(&impulse);
    free(late);

    // Other files: .irs is a WAV by another name, FLAC, 16-bit; a missing file, 3 channels.
    [NSFileManager.defaultManager removeItemAtPath:irPath(@"dirac.irs") error:nil];
    [NSFileManager.defaultManager copyItemAtPath:irPath(@"dirac-stereo.wav") toPath:irPath(@"dirac.irs") error:nil];
    ok = SGDSPEngineSetConvolver(engine, true, irPath(@"dirac.irs").UTF8String, 0, error, sizeof error);
    CHECK(ok, ".irs reads as a WAV");
    writeImpulse(@"random-4.flac", kAudioFileFLACType, random, 4, length, kRate, 24);
    ok = SGDSPEngineSetConvolver(engine, true, irPath(@"random-4.flac").UTF8String, 0, error, sizeof error);
    CHECK(ok, "a 4 channel FLAC reads%s%s", ok ? "" : ": ", ok ? "" : error);
    writeImpulse(@"random-4-16bit.wav", kAudioFileWAVEType, random, 4, length, kRate, 16);
    ok = SGDSPEngineSetConvolver(engine, true, irPath(@"random-4-16bit.wav").UTF8String, 0, error, sizeof error);
    CHECK(ok, "a 16-bit WAV reads");
    ok = SGDSPEngineSetConvolver(engine, true, "/nonexistent.wav", 0, error, sizeof error);
    CHECK(!ok, "a missing file: \"%s\"", error);
    writeImpulse(@"three.wav", kAudioFileWAVEType, random, 3, 1000, kRate, 32);
    ok = SGDSPEngineSetConvolver(engine, true, irPath(@"three.wav").UTF8String, 0, error, sizeof error);
    CHECK(!ok, "3 channels: \"%s\"", error);
    for (int p = 0; p < 4; p++) {
        free(dirac[p]);
        free(random[p]);
    }
    SGDSPEngineFree(engine);
}

#pragma mark - DDC and Liveprog

// A .vdc of a peak (+6 dB at 1 kHz) and a low shelf (+4 dB at 80 Hz), the feedback added (sign 1) or subtracted.
static NSString *ddcText(int sign) {
    NSMutableString *text = [NSMutableString string];
    const double rates[2] = {44100, 48000};
    for (int r = 0; r < 2; r++) {
        SGBiquad q[2] = {SGBiquadPeak(rates[r], 1000, 1, 6), SGBiquadLowShelf(rates[r], 80, M_SQRT1_2, 4)};
        [text appendFormat:@"SR_%.0f:", rates[r]];
        for (int i = 0; i < 2; i++) {
            [text appendFormat:@"%s%.12g,%.12g,%.12g,%.12g,%.12g", i ? "," : "", q[i].b0, q[i].b1, q[i].b2, -sign * q[i].a1, -sign * q[i].a2];
        }
        [text appendString:@"\n"];
    }
    return text;
}

static void checkDDC(void) {
    printf("\nViPER DDC\n");
    char error[300] = "";
    const double rates[] = {48000, 44100, 96000};
    for (int r = 0; r < 3; r++) {
        for (int sign = 1; sign >= -1; sign -= 2) {
            SGDSPEngine *engine = SGDSPEngineCreate(rates[r]);
            allOff(engine);
            SGDSPEngineSetOutput(engine, -12, -0.1, 60);
            bool ok = SGDSPEngineSetDDC(engine, true, ddcText(sign).UTF8String, error, sizeof error);
            double peak = stepGain(engine, 1000, 0.25, rates[r], NULL) + 12, shelf = stepGain(engine, 25, 0.25, rates[r], NULL) + 12;
            double flat = stepGain(engine, 12000, 0.25, rates[r], NULL) + 12;
            CHECK(ok && fabs(peak - 6.06) < 0.25 && fabs(shelf - 4) < 0.25 && fabs(flat) < 0.4,
                  "%.1f kHz, feedback %s: 1 kHz %+.2f dB, 25 Hz %+.2f dB, 12 kHz %+.2f dB%s", rates[r] / 1000, sign > 0 ? "added     " : "subtracted",
                  peak, shelf, flat, ok ? "" : error);
            SGDSPEngineFree(engine);
        }
    }
    SGDSPEngine *engine = SGDSPEngineCreate(kRate);
    bool ok = SGDSPEngineSetDDC(engine, true, "SR_44100:1,2,3\nSR_48000:1,2,3,", error, sizeof error);
    CHECK(!ok, "a malformed file is refused: \"%s\"", error);
    bool oneWay = SGDSPEngineSetDDC(engine, true, "SR_44100:1,0,0,1.5,0.9\nSR_48000:1,0,0,1.5,0.9", error, sizeof error);
    bool neither = SGDSPEngineSetDDC(engine, true, "SR_44100:1,0,0,2.5,-1.9\nSR_48000:1,0,0,2.5,-1.9", error, sizeof error);
    CHECK(oneWay && !neither, "filters stable one way load, unstable both ways are refused: \"%s\"", error);
    SGDSPEngineFree(engine);
}

static void checkLiveprog(void) {
    printf("\nLiveprog\n");
    char error[300] = "";
    SGDSPEngine *engine = SGDSPEngineCreate(kRate);
    allOff(engine);
    bool ok = SGDSPEngineSetLiveprog(engine, true, "desc: swap\n@sample\nt = spl0;\nspl0 = spl1;\nspl1 = t;\n", error, sizeof error);
    Audio left = tone(1000, 0.5, 1, kRate, true);
    run(engine, left, kPattern1024);
    double l = toneLevel(left.left + 24000, 24000, 1000, kRate), r = toneLevel(left.right + 24000, 24000, 1000, kRate);
    CHECK(ok && l < -120 && fabs(r - 20 * log10(0.5)) < 0.01, "a script swapping the channels: left %.0f dB, right %.2f dB", l, r);
    freeAudio(left);

    const char *gain = "desc: gain\n// a comment\nslider1:-6<-24,24,0.1>Gain (dB)\n\n@init\ng = 10^(slider1/20);\n@sample\nspl0 *= g;\nspl1 *= g;\n";
    ok = SGDSPEngineSetLiveprog(engine, true, gain, error, sizeof error);
    double measured = stepGain(engine, 1000, 0.5, kRate, NULL);
    CHECK(ok && fabs(measured + 6) < 0.01, "slider1's default reaches @init: %+.3f dB", measured);

    const char *delay = "@init\nsize = srate / 2;\npos = 0;\nfreembuf(size + 1);\n@sample\nd = pos[0];\npos[0] = spl0;\n"
                        "pos += 1;\npos >= size ? pos = 0;\nspl0 = d;\nspl1 = gmem[3] + stack_push(spl1) * 0 + stack_pop();\n";
    ok = SGDSPEngineSetLiveprog(engine, true, delay, error, sizeof error);
    Audio pulse = makeAudio((size_t)kRate * 2);
    pulse.left[10000] = 1;
    SGDSPEngineRestart(engine);
    atomic_store(&sg_renderAllocations, 0);
    run(engine, pulse, kPatternMixed);
    unsigned allocations = atomic_load(&sg_renderAllocations);
    (void)allocations;
    size_t at = 0;
    for (size_t i = 0; i < pulse.frames; i++) {
        if (pulse.left[i] > 0.5f) at = i;
    }
    CHECK(ok && at == 10000 + kSGDSPEngineBlock + 24000, "a half-second delay line in the script's memory: the pulse at %zu comes out at %zu%s", (size_t)10000, at,
          ok ? "" : error);
#if SG_COUNTS_ALLOCATIONS
    CHECK(allocations == 0, "memory, gmem, the stack and freembuf in a script: %u allocations on the render thread", allocations);
#endif
    freeAudio(pulse);

    SGDSPEngineFree(engine);
    engine = SGDSPEngineCreate(kRate);
    allOff(engine);
    ok = SGDSPEngineSetLiveprog(engine, true, "@block\nn += 1;\n@sample\nspl0 = n / 1000;\nspl1 = samplesblock / 10000;\n", error, sizeof error);
    Audio blocks = makeAudio(kSGDSPEngineBlock * 4);
    SGDSPEngineRestart(engine);
    run(engine, blocks, kPattern1024);
    CHECK(ok && blocks.left[blocks.frames - 1] == 0.003f && blocks.right[blocks.frames - 1] == 0.1024f, "@block runs once a block, with samplesblock: %g blocks, %g",
          blocks.left[blocks.frames - 1] * 1000, blocks.right[blocks.frames - 1] * 10000);
    freeAudio(blocks);

    ok = SGDSPEngineSetLiveprog(engine, true, "desc: broken\n// a comment\n@init\nx = 1;\ny = (2 + ;\n@sample\nspl0 = spl0;\n", error, sizeof error);
    CHECK(!ok && !strncmp(error, "Line 5:", 7), "a script broken in @init at line 5: \"%s\"", error);
    ok = SGDSPEngineSetLiveprog(engine, true, "desc: broken\n@init\nx = 1;\n@sample\nspl0 = spl0;\nspl1 = spl1 * ;\n", error, sizeof error);
    CHECK(!ok && !strncmp(error, "Line 6:", 7), "a script broken in @sample at line 6: \"%s\"", error);
    ok = SGDSPEngineSetLiveprog(engine, true, "@sample\nspl0 = nosuchfunction(spl0);\n", error, sizeof error);
    CHECK(!ok && !strncmp(error, "Line 2:", 7), "an unknown function: \"%s\"", error);
    ok = SGDSPEngineSetLiveprog(engine, true, "desc: none\nspl0 = 0;\n", error, sizeof error);
    CHECK(!ok, "a script without @sample: \"%s\"", error);
    const char *functions = "@init\nfunction twice(x) ( x * 2; );\n@sample\nspl0 = twice(spl0) * 0.5;\nspl1 = sin(0) + spl1;\n";
    ok = SGDSPEngineSetLiveprog(engine, true, functions, error, sizeof error);
    measured = stepGain(engine, 440, 0.5, kRate, NULL);
    CHECK(ok && fabs(measured) < 0.001, "a function from @init called in @sample: %+.4f dB%s%s", measured, ok ? "" : ": ", ok ? "" : error);
    SGDSPEngineFree(engine);
}

#pragma mark - reverb, stereo, crossfeed, tube, compander

static void checkReverb(void) {
    printf("\nreverb\n");
    static const char *names[SGDSPReverbPresetCount] = {"ambience", "small room", "medium room", "large room", "chamber", "plate", "small hall",
                                                        "large hall", "cathedral"};
    double times[SGDSPReverbPresetCount];
    char line[400] = "";
    bool finite = true;
    for (int p = 0; p < SGDSPReverbPresetCount; p++) {
        SGDSPEngine *engine = SGDSPEngineCreate(kRate);
        allOff(engine);
        SGDSPEngineSetReverb(engine, true, p);
        Audio impulse = makeAudio((size_t)kRate * 12);
        impulse.left[kSGDSPEngineBlock * 2] = impulse.right[kSGDSPEngineBlock * 2] = 0.5f;
        run(engine, impulse, kPattern1024);
        float peak;
        finite = finite && finiteAndBounded(impulse, 1, &peak);
        // The wet part only: the dry impulse is one sample.
        impulse.left[kSGDSPEngineBlock * 3] = 0;
        times[p] = reverberationTime(impulse.left + kSGDSPEngineBlock * 3, impulse.frames - kSGDSPEngineBlock * 3, kRate);
        snprintf(line + strlen(line), sizeof line - strlen(line), "%s%s %.1f s", p ? ", " : "", names[p], times[p]);
        freeAudio(impulse);
        SGDSPEngineFree(engine);
    }
    CHECK(finite && times[0] < times[2] && times[2] < times[3] && times[6] < times[7] && times[7] < times[8], "tails by preset: %s", line);
}

static void checkWide(void) {
    printf("\nstereo widening\n");
    SGDSPEngine *engine = SGDSPEngineCreate(kRate);
    allOff(engine);
    SGDSPEngineSetStereoWide(engine, true, 75);
    Audio mono = tone(700, 0.3, 1, kRate, false);
    run(engine, mono, kPatternOdd);
    size_t same = 0;
    for (size_t i = 0; i < mono.frames; i++) same += mono.left[i] == mono.right[i];
    CHECK(same == mono.frames, "mono in stays mono at 150%%: %zu of %zu frames the same in both channels", same, mono.frames);
    freeAudio(mono);
    Audio side = makeAudio((size_t)kRate);
    for (size_t i = 0; i < side.frames; i++) side.left[i] = -(side.right[i] = (float)(0.2 * sin(2 * M_PI * 3000 * i / kRate)));
    run(engine, side, kPatternOdd);
    double level = toneLevel(side.left + 24000, 24000, 3000, kRate) - 20 * log10(0.2);
    CHECK(fabs(level - 20 * log10(1.5)) < 0.05, "a side-only 3 kHz tone at 150%%: %+.2f dB (1.5 times is %+.2f)", level, 20 * log10(1.5));
    freeAudio(side);
    SGDSPEngineSetStereoWide(engine, true, 0);
    Audio left = tone(1000, 0.5, 1, kRate, true);
    run(engine, left, kPattern1024);
    double l = toneLevel(left.left + 24000, 24000, 1000, kRate), r = toneLevel(left.right + 24000, 24000, 1000, kRate);
    CHECK(fabs(l - r) < 0.01, "at 0%% a left-only tone comes out in the middle: left %.2f dB, right %.2f dB", l, r);
    freeAudio(left);
    SGDSPEngineFree(engine);
}

static void checkCrossfeed(void) {
    printf("\ncrossfeed\n");
    static const char *names[] = {"Jan Meier", "Chu Moy", "default"};
    double feeds[3];
    for (int p = 0; p < 3; p++) {
        SGDSPEngine *engine = SGDSPEngineCreate(kRate);
        allOff(engine);
        SGDSPEngineSetCrossfeed(engine, true, p);
        Audio mono = tone(300, 0.3, 1, kRate, false);
        run(engine, mono, kPatternMixed);
        size_t same = 0;
        for (size_t i = 0; i < mono.frames; i++) same += mono.left[i] == mono.right[i];
        Audio left = tone(100, 0.3, 1, kRate, true);
        run(engine, left, kPattern1024);
        feeds[p] = toneLevel(left.right + 24000, 24000, 100, kRate) - toneLevel(left.left + 24000, 24000, 100, kRate);
        CHECK(same == mono.frames, "%-9s mono stays mono (%zu of %zu frames), a left-only 100 Hz tone reaches the right at %.1f dB of the left", names[p], same,
              mono.frames, feeds[p]);
        freeAudio(mono);
        freeAudio(left);
        SGDSPEngineFree(engine);
    }
    CHECK(feeds[0] < feeds[1] && feeds[1] < feeds[2], "the presets run lightest to strongest");
}

static void checkTube(void) {
    printf("\nanalog modelling\n");
    SGDSPEngine *engine = SGDSPEngineCreate(kRate);
    allOff(engine);
    SGDSPEngineSetTube(engine, true, 6);
    double quiet = stepGain(engine, 1000, 0.01, kRate, NULL);
    CHECK(fabs(quiet) < 0.1, "6 dB of drive, a 1 kHz tone at -40 dBFS keeps its level: %+.3f dB", quiet);
    Audio loud = tone(1000, 0.5, 1, kRate, false);
    run(engine, loud, kPattern1024);
    double h1 = toneLevel(loud.left + 24000, 24000, 1000, kRate), h2 = toneLevel(loud.left + 24000, 24000, 2000, kRate) - h1;
    double h3 = toneLevel(loud.left + 24000, 24000, 3000, kRate) - h1;
    CHECK(h2 > h3 && h2 < -10, "at -6 dBFS: 2nd harmonic %.1f dBc, 3rd %.1f dBc", h2, h3);
    freeAudio(loud);
    SGDSPEngineSetTube(engine, true, 12);
    Audio high = tone(15000, 0.7, 1, kRate, false);
    run(engine, high, kPattern1024);
    double fundamental = toneLevel(high.left + 24000, 24000, 15000, kRate);
    double alias3 = toneLevel(high.left + 24000, 24000, 3000, kRate) - fundamental, alias2 = toneLevel(high.left + 24000, 24000, 18000, kRate) - fundamental;
    CHECK(alias3 < -50 && alias2 < -50, "12 dB of drive, 15 kHz at -3 dBFS: the 3rd harmonic's alias at 3 kHz %.1f dBc, the 2nd's at 18 kHz %.1f dBc", alias3, alias2);
    freeAudio(high);
    SGDSPEngineFree(engine);
    engine = SGDSPEngineCreate(kRate);
    allOff(engine);
    SGDSPEngineSetTube(engine, true, -3);
    Audio click = makeAudio(8192);
    click.left[3000] = 0.01f;
    run(engine, click, kPattern1024);
    size_t at = 0;
    for (size_t i = 0; i < click.frames; i++) {
        if (fabsf(click.left[i]) > fabsf(click.left[at])) at = i;
    }
    CHECK(at - 3000 - kSGDSPEngineBlock <= 6, "a click comes out %zu frames after the engine's block: the oversampling filters' own delay, minimum phase",
          at - 3000 - kSGDSPEngineBlock);
    freeAudio(click);
    SGDSPEngineFree(engine);
}

static void checkCompander(void) {
    printf("\ncompander\n");
    double zeros[7] = {0}, plus[7] = {1, 1, 1, 1, 1, 1, 1}, minus[7] = {-1, -1, -1, -1, -1, -1, -1};
    SGDSPEngine *engine = SGDSPEngineCreate(kRate);
    allOff(engine);
    SGDSPEngineSetCompander(engine, true, 0.22, kCompanderFrequencies, zeros);
    double worst = 0;
    for (int i = 0; i < 24; i++) worst = fmax(worst, fabs(stepGain(engine, 30 * pow(600, i / 23.0), 0.25, kRate, NULL)));
    CHECK(worst < 0.02, "every band at 0: flat from 30 Hz to 18 kHz within %.4f dB", worst);
    SGDSPEngineFree(engine);
    const double *settings[] = {plus, minus};
    for (int s = 0; s < 2; s++) {
        engine = SGDSPEngineCreate(kRate);
        allOff(engine);
        SGDSPEngineSetCompander(engine, true, 0.22, kCompanderFrequencies, settings[s]);
        Audio bursts = makeAudio((size_t)kRate * 12);
        for (size_t i = 0; i < bursts.frames; i++) {
            double amplitude = (i / (size_t)kRate) % 2 ? pow(10, -30 / 20.0) : pow(10, -6 / 20.0);
            bursts.left[i] = bursts.right[i] = (float)(amplitude * sin(2 * M_PI * 1000 * i / kRate));
        }
        run(engine, bursts, kPattern1024);
        size_t loud = (size_t)kRate * 10 + kSGDSPEngineBlock + 24000, soft = (size_t)kRate * 11 + kSGDSPEngineBlock + 24000;
        double range = toneLevel(bursts.left + loud, 12000, 1000, kRate) - toneLevel(bursts.left + soft, 12000, 1000, kRate);
        CHECK(s == 0 ? range < 18 : range > 27, "every band at %+.1f, 1 kHz bursts 24 dB apart come out %.1f dB apart", settings[s][0], range);
        freeAudio(bursts);
        SGDSPEngineFree(engine);
    }
}

#pragma mark - crossfades, everything on, rates

typedef enum {
    kCompander, kBass, kEqualizer, kGraphicEq, kConvolver, kDDC, kLiveprog, kReverb, kWide, kCrossfeed, kTube, kEffectCount
} Effect;

static const char *kEffectNames[] = {
    "compander", "bass boost 5 dB", "equalizer", "Graphic EQ", "convolver 2.5 s room", "DDC", "Liveprog stereo script", "reverb plate",
    "stereo wide 60%", "crossfeed", "tube 2 dB",
};

static bool setEffect(SGDSPEngine *engine, Effect effect, bool on) {
    char error[300] = "";
    static const double companderGains[7] = {0.3, 0.2, 0, -0.1, 0.1, 0.3, 0.4};
    static const double eqGains[15] = {4, 3, 2, 1, 0, -1, -1, 0, 1, 2, 3, 2, 1, 0, -2};
    bool ok = true;
    switch (effect) {
    case kCompander: SGDSPEngineSetCompander(engine, on, 0.22, kCompanderFrequencies, companderGains); break;
    case kBass: SGDSPEngineSetBassBoost(engine, on, 5); break;
    case kEqualizer: SGDSPEngineSetEqualizer(engine, on, kEqFrequencies, eqGains); break;
    case kGraphicEq:
        ok = SGDSPEngineSetGraphicEq(engine, on, "GraphicEQ: 20 4; 60 3; 200 0; 1000 -1; 3000 2; 8000 1; 16000 -3; 20000 -6", error, sizeof error);
        break;
    case kConvolver: ok = SGDSPEngineSetConvolver(engine, on, irPath(@"room.wav").UTF8String, 0, error, sizeof error); break;
    case kDDC: ok = SGDSPEngineSetDDC(engine, on, ddcText(1).UTF8String, error, sizeof error); break;
    case kLiveprog:
        ok = SGDSPEngineSetLiveprog(engine, on, "desc: width\n@init\nw = 0.3;\n@sample\nm = (spl0 + spl1) / 2;\ns = (spl0 - spl1) / 2 * (1 + w);\nspl0 = m + s;\nspl1 = m - s;\n",
                                    error, sizeof error);
        break;
    case kReverb: SGDSPEngineSetReverb(engine, on, 5); break;
    case kWide: SGDSPEngineSetStereoWide(engine, on, 60); break;
    case kCrossfeed: SGDSPEngineSetCrossfeed(engine, on, 2); break;
    case kTube: SGDSPEngineSetTube(engine, on, 2); break;
    default: break;
    }
    if (!ok) printf("         %s: %s\n", kEffectNames[effect], error);
    return ok;
}

static void allOn(SGDSPEngine *engine) {
    for (Effect e = 0; e < kEffectCount; e++) setEffect(engine, e, true);
}

// A 2.5 s stereo room: decaying noise, the far channel a little later.
static void makeRoom(void) {
    size_t length = (size_t)(kRate * 2.5);
    float *paths[2] = {malloc(length * 4), malloc(length * 4)};
    srand(3);
    for (int p = 0; p < 2; p++) {
        for (size_t i = 0; i < length; i++) {
            double decay = exp(-6.9 * i / length);
            paths[p][i] = (float)((rand() / (double)RAND_MAX - 0.5) * decay * (i < 200 + 30 * p ? 0 : 1));
        }
        paths[p][30 * p] = 1;
    }
    writeImpulse(@"room.wav", kAudioFileWAVEType, paths, 2, length, kRate, 32);
    free(paths[0]);
    free(paths[1]);
}

// The largest bend in a signal (its second difference) from `from` to `to`.
static double worstKink(const float *samples, size_t from, size_t to) {
    double worst = 0;
    for (size_t i = from + 1; i + 1 < to; i++) worst = fmax(worst, fabs(samples[i + 1] - 2.0 * samples[i] + samples[i - 1]));
    return worst;
}

// A tone with the effect switched on, off and on again (the convolver's response swapped the second time):
// no bend sharper than the effect makes on its own, on or off. A room made anew hears the tone start mid-note
// as it fades in, its first reflections with it, so reverb and convolver get a little more.
static void checkCrossfades(void) {
    printf("\ncrossfades: effects switched on, off and swapped under a 440 Hz tone\n");
    enum { kSegment = 21000 };
    for (Effect e = 0; e < kEffectCount; e++) {
        SGDSPEngine *engine = SGDSPEngineCreate(kRate);
        allOff(engine);
        Audio sine = tone(440, 0.5, 3, kRate, false);
        sg_renderThread = pthread_self();
        for (int step = 0; step < 6; step++) {
            if (step == 1 || step == 3 || step == 5) setEffect(engine, e, step != 3);
            if (step == 5 && e == kConvolver) SGDSPEngineSetConvolver(engine, true, irPath(@"random-4.wav").UTF8String, 0, NULL, 0);
            SGDSPEngineProcess(engine, sine.left + step * kSegment, sine.right + step * kSegment, kSegment);
        }
        // Steady stretches between the switches, and the few blocks after each switch where its fade falls.
        double steady = 0, switching = 0;
        for (int step = 0; step < 6; step++) {
            size_t start = (size_t)step * kSegment;
            if (step % 2 == 0) steady = fmax(steady, worstKink(sine.left, start + kSGDSPEngineBlock * 4, start + kSegment));
            else switching = fmax(switching, worstKink(sine.left, start, start + kSGDSPEngineBlock * 4));
            if (step % 2 == 1) steady = fmax(steady, worstKink(sine.left, start + kSGDSPEngineBlock * 4, start + kSegment));
        }
        CHECK(switching <= (e == kReverb || e == kConvolver ? 1.5 : 1.25) * steady, "%-24s the sharpest bend while switching is %.2f times the sharpest steady one", kEffectNames[e], switching / steady);
        freeAudio(sine);
        SGDSPEngineFree(engine);
    }
}

static void checkAllOn(Audio song) {
    printf("\nevery effect on\n");
    SGDSPEngine *engine = SGDSPEngineCreate(kRate);
    allOff(engine);
    allOn(engine);
    Audio output = copyAudio(song);
    atomic_store(&sg_renderAllocations, 0);
    Timing timing = run(engine, output, kPatternMixed);
    (void)timing;
    float peak = 0;
    bool fine = finiteAndBounded(output, 0.98856f, &peak);
    CHECK(fine, "no NaN or infinity and nothing over the limiter's threshold: peak %.4f (%.2f dBFS)", peak, 20 * log10(peak));
    SGDSPEngineStats stats = SGDSPEngineReadStats(engine, true);
    CHECK(stats.faults == 0, "no block silenced as not finite (%llu of %llu)", stats.faults, stats.blocks);
#if SG_COUNTS_ALLOCATIONS
    unsigned allocations = atomic_load(&sg_renderAllocations);
    CHECK(allocations == 0, "no allocation or free on the render thread over %llu calls in mixed slices, Apple's reverb unit included (%u)", timing.calls,
          allocations);
#endif
    writeSong(@"all-on.wav", output);
    freeAudio(output);
    SGDSPEngineFree(engine);
}

static void checkRateAndReset(Audio song) {
    printf("\nsample rate change and reset\n");
    SGDSPEngine *engine = SGDSPEngineCreate(kRate);
    allOff(engine);
    allOn(engine);
    Audio a = copyAudio(song);
    a.frames = (size_t)kRate * 3;
    run(engine, a, kPattern1024);
    const double rates[] = {44100, 96000, 22050};
    for (int r = 0; r < 3; r++) {
        SGDSPEngineSetSampleRate(engine, rates[r]);
        allOn(engine);
        Audio b = copyAudio(song);
        b.frames = (size_t)rates[r] * 2;
        run(engine, b, kPattern4096);
        float peak = 0;
        CHECK(SGDSPEngineSampleRate(engine) == rates[r] && finiteAndBounded(b, 0.98856f, &peak), "-> %.2f kHz with every effect on: runs finite, peak %.3f",
              rates[r] / 1000, peak);
        freeAudio(b);
    }
    SGDSPEngineSetSampleRate(engine, kRate);
    allOn(engine);
    SGDSPEngineReset(engine);
    SGDSPEngineSetOutput(engine, 0, -0.1, 60);
    SGDSPEngineRestart(engine);
    Audio quiet = copyAudio(song);
    quiet.frames = (size_t)kRate * 3;
    Audio out = copyAudio(quiet);
    run(engine, out, kPatternMixed);
    float largest;
    size_t differ = delayedDifferences(quiet, out, &largest);
    CHECK(differ == 0, "after a reset every effect is off and the output is the input one block later (%zu differ)", differ);
    freeAudio(a);
    freeAudio(quiet);
    freeAudio(out);
    SGDSPEngineFree(engine);
}

static void checkCost(Audio song) {
    printf("\ncost per 1024-frame block at 48 kHz (21.33 ms of sound), 20 s of the song\n");
    SGDSPEngine *engine = SGDSPEngineCreate(kRate);
    allOff(engine);
    Audio clip = copyAudio(song);
    clip.frames = MIN(clip.frames, (size_t)kRate * 20);
    double blockMS = kSGDSPEngineBlock / kRate * 1000;
    for (int e = -1; e <= kEffectCount; e++) {
        const char *name = e < 0 ? "every effect off" : e == kEffectCount ? "every effect on" : kEffectNames[e];
        if (e == kEffectCount) allOn(engine);
        else if (e >= 0) setEffect(engine, (Effect)e, true);
        Audio out = copyAudio(clip);
        Timing timing = run(engine, out, kPattern1024);
        SGDSPEngineStats stats = SGDSPEngineReadStats(engine, true);
        printf("         %-26s %7.3f ms a call (%5.2f%% of real time), the worst block %6.3f ms\n", name, timing.meanMS, timing.meanMS / blockMS * 100,
               stats.peakMS);
        freeAudio(out);
        if (e >= 0 && e < kEffectCount) setEffect(engine, (Effect)e, false);
        SGDSPEngineCollect(engine);
    }
    freeAudio(clip);
    SGDSPEngineFree(engine);
}

#pragma mark - stress

typedef struct {
    SGDSPEngine *engine;
    atomic_bool stop;
    unsigned changes;
    bool effectsOn;
    useconds_t pause;
    double longestMS;
} Hammer;

static void *hammer(void *context) {
    Hammer *h = context;
    char error[300];
    double zeros[15] = {0};
    unsigned i = 0;
    while (!atomic_load(&h->stop)) {
        uint64_t start = mach_absolute_time();
        if (!h->effectsOn) {
            // Setters that leave the sound as it is, so every block, processed or passed dry, must be exact.
            switch (i % 6) {
            case 0: SGDSPEngineSetOutput(h->engine, 0, -0.1, 60); break;
            case 1: SGDSPEngineSetReverb(h->engine, false, 5); break;
            case 2: SGDSPEngineSetEqualizer(h->engine, false, kEqFrequencies, zeros); break;
            case 3: SGDSPEngineSetCrossfeed(h->engine, false, 2); break;
            case 4: SGDSPEngineSetLiveprog(h->engine, false, NULL, error, sizeof error); break;
            case 5: SGDSPEngineCollect(h->engine); break;
            }
        } else {
            setEffect(h->engine, (Effect)(i % kEffectCount), (i / kEffectCount) % 2 == 0);
            if (i % 7 == 0) SGDSPEngineSetOutput(h->engine, (i % 7) - 3.0, -0.1 - (i % 5), 30 + i % 100);
        }
        h->longestMS = fmax(h->longestMS, ticksToMS(mach_absolute_time() - start));
        i++;
        h->changes++;
        if (h->pause) usleep(h->pause);
    }
    return NULL;
}

static void runHammered(Hammer *h, Audio out, double speed) {
    pthread_t thread;
    pthread_create(&thread, NULL, hammer, h);
    uint64_t began = mach_absolute_time();
    size_t index = 0;
    for (size_t done = 0; done < out.frames;) {
        uint32_t frames = (uint32_t)MIN((size_t)sliceAt(kPatternMixed, index++), out.frames - done);
        SGDSPEngineProcess(h->engine, out.left + done, out.right + done, frames);
        done += frames;
        if (speed > 0) {
            double due = done / kRate / speed * 1000, elapsed = ticksToMS(mach_absolute_time() - began);
            if (due > elapsed) usleep((useconds_t)((due - elapsed) * 1000));
        }
    }
    atomic_store(&h->stop, true);
    pthread_join(thread, NULL);
}

static void checkStress(Audio song, bool quick) {
    printf("\na thread changing settings while another processes\n");
    Hammer h = {.engine = SGDSPEngineCreate(kRate)};
    allOff(h.engine);
    Audio quiet = copyAudio(song);
    quiet.frames = MIN(quiet.frames, (size_t)kRate * (quick ? 8 : 30));
    scaleAudio(quiet, 0.5f);
    Audio out = copyAudio(quiet);
    runHammered(&h, out, 0);
    SGDSPEngineStats stats = SGDSPEngineReadStats(h.engine, true);
    float largest = 0, peak = 0;
    size_t differ = delayedDifferences(quiet, out, &largest);
    CHECK(differ == 0, "settings that leave the sound alone, %u changes: %llu blocks processed, %llu passed dry, %zu samples off the input one block earlier",
          h.changes, stats.blocks, stats.dry, differ);
    freeAudio(out);
    SGDSPEngineFree(h.engine);

    Hammer e = {.engine = SGDSPEngineCreate(kRate), .effectsOn = true};
    allOff(e.engine);
    out = copyAudio(quiet);
    runHammered(&e, out, 0);
    stats = SGDSPEngineReadStats(e.engine, true);
    CHECK(finiteAndBounded(out, 0.98856f, &peak) && stats.faults == 0, "every effect switched on and off as fast as it goes, %u changes: %llu blocks, %llu dry, finite, peak %.3f",
          e.changes, stats.blocks, stats.dry, peak);
    freeAudio(out);
    SGDSPEngineFree(e.engine);

    Hammer p = {.engine = SGDSPEngineCreate(kRate), .effectsOn = true, .pause = 30000};
    allOff(p.engine);
    out = copyAudio(quiet);
    out.frames = MIN(out.frames, (size_t)kRate * (quick ? 4 : 10));
    runHammered(&p, out, 1);
    stats = SGDSPEngineReadStats(p.engine, true);
    CHECK(finiteAndBounded(out, 0.98856f, &peak) && stats.faults == 0,
          "a change every 30 ms in real time, %u changes: %llu blocks processed, %llu dry (%.2f%%), the longest setter %.1f ms, peak %.3f", p.changes, stats.blocks,
          stats.dry, 100.0 * stats.dry / (stats.blocks + stats.dry), p.longestMS, peak);
    freeAudio(out);
    freeAudio(quiet);
    SGDSPEngineFree(p.engine);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        setvbuf(stdout, NULL, _IOLBF, 0);
        if (argc < 3) {
            printf("usage: %s <song> <out dir> [stress]\n", argv[0]);
            return 2;
        }
        sg_outDir = @(argv[2]);
        bool stressOnly = argc > 3 && !strcmp(argv[3], "stress");
        [NSFileManager.defaultManager createDirectoryAtPath:sg_outDir withIntermediateDirectories:YES attributes:nil error:nil];
#if SG_COUNTS_ALLOCATIONS
        malloc_logger = countAllocation;
#endif
        Audio song = decode(@(argv[1]), kRate, stressOnly ? 12 : 60);
        printf("song: %.1f s at %.0f Hz\n", song.frames / kRate, kRate);
        makeRoom();
        if (stressOnly) {
            checkConvolver(song);
            checkStress(song, true);
            checkRateAndReset(song);
            checkLiveprog();
        } else {
            checkBypass(song);
            checkRestart(song);
            checkOutput(song);
            checkEqualizer();
            checkBass();
            checkGraphicEq();
            checkConvolver(song);
            checkDDC();
            checkLiveprog();
            checkReverb();
            checkWide();
            checkCrossfeed();
            checkTube();
            checkCompander();
            checkCrossfades();
            checkAllOn(song);
            checkRateAndReset(song);
            checkStress(song, false);
            checkCost(song);
        }
        printf("\n%s: %d failed\n", sg_failures ? "FAILED" : "all passed", sg_failures);
        return sg_failures ? 1 : 0;
    }
}
