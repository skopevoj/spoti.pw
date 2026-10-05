// Runs SGTimePitch.m on the Mac both ways the tweak runs it: in place over IO buffers of Spotify's sizes
// (pitch alone), and pulling a source at a rate (speed, with or without pitch, or as a varispeed with the
// pitch going along). Checks a sine comes out at the pitch asked for and the source is consumed at the rate
// asked for, reports the unit's pulls, underruns, delay, cost and how much of the sine is not a sine, and
// writes a song shifted up and down, and at 1.25x both ways pitch can follow, to listen to.
//
//     ./build.sh && build/pitch [song]
#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <mach/mach_time.h>
#import "Shared/Player/SGTimePitch.h"

static const double kRate = 44100;

// Frequency by the zero crossings of the steady part.
static double frequency(const float *samples, size_t count) {
    size_t first = 0, last = 0, crossings = 0;
    for (size_t i = 1; i < count; i++) {
        if (samples[i - 1] < 0 && samples[i] >= 0) {
            if (!crossings) first = i;
            last = i;
            crossings++;
        }
    }
    return crossings > 1 ? (crossings - 1) * kRate / (last - first) : 0;
}

// The frame where the output first gets loud: the delay the shifter adds.
static size_t onset(const float *samples, size_t count) {
    for (size_t i = 0; i < count; i++) if (fabsf(samples[i]) > 0.1f) return i;
    return count;
}

static UInt32 bufferSize(size_t index, int pattern) {
    if (pattern == 0) return 1024;
    if (pattern == 1) return 4096;
    static const UInt32 odd[] = {470, 471, 512, 1024, 256, 941};
    return odd[index % 6];
}

static void runSine(float semitones, int pattern) {
    size_t total = (size_t)(kRate * 3);
    float *left = calloc(total, sizeof(float)), *right = calloc(total, sizeof(float));
    for (size_t i = 0; i < total; i++) left[i] = right[i] = 0.5f * sinf(2 * M_PI * 440 * i / kRate);
    SGTimePitch *shifter = SGTimePitchCreate(kRate, 2, NULL, NULL);
    if (!shifter) {
        printf("no shifter\n");
        exit(1);
    }
    SGTimePitchSetSemitones(shifter, semitones);
    SGTimePitchReset(shifter);
    uint64_t start = mach_absolute_time();
    size_t done = 0, index = 0;
    while (done < total) {
        UInt32 frames = (UInt32)MIN((size_t)bufferSize(index++, pattern), total - done);
        float *channels[2] = {left + done, right + done};
        if (!SGTimePitchProcess(shifter, channels, frames)) printf("  process failed at %zu\n", done);
        done += frames;
    }
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    double seconds = (mach_absolute_time() - start) * (double)timebase.numer / timebase.denom / 1e9;
    double expected = 440 * pow(2, semitones / 12);
    double measured = frequency(left + (size_t)kRate, total - (size_t)kRate);
    printf("sine %+5.1f st, buffers %-8s: %6.1f Hz (want %6.1f, %+.2f%%), delay %4zu frames (unit %.1f ms), largest pull %u, underruns %u, failures %u, cost %.2f%% of real time\n",
           semitones, pattern == 0 ? "1024" : pattern == 1 ? "4096" : "mixed", measured, expected, (measured / expected - 1) * 100,
           onset(left, total), SGTimePitchLatency(shifter) * 1000, SGTimePitchLargestPull(shifter),
           SGTimePitchUnderruns(shifter), SGTimePitchFailures(shifter), seconds / 3 * 100);
    free(left);
    free(right);
}

static void runSong(NSString *path, float semitones, NSString *outPath) {
    ExtAudioFileRef file;
    if (ExtAudioFileOpenURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], &file)) {
        printf("cannot open %s\n", path.UTF8String);
        return;
    }
    AudioStreamBasicDescription format = {
        .mSampleRate = kRate, .mFormatID = kAudioFormatLinearPCM,
        .mFormatFlags = kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
        .mBytesPerPacket = 4, .mFramesPerPacket = 1, .mBytesPerFrame = 4, .mChannelsPerFrame = 2, .mBitsPerChannel = 32,
    };
    ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat, sizeof format, &format);
    ExtAudioFileRef output;
    AudioStreamBasicDescription wav = {
        .mSampleRate = kRate, .mFormatID = kAudioFormatLinearPCM,
        .mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
        .mBytesPerPacket = 4, .mFramesPerPacket = 1, .mBytesPerFrame = 4, .mChannelsPerFrame = 2, .mBitsPerChannel = 16,
    };
    ExtAudioFileCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:outPath], kAudioFileWAVEType, &wav, NULL, kAudioFileFlags_EraseFile, &output);
    ExtAudioFileSetProperty(output, kExtAudioFileProperty_ClientDataFormat, sizeof format, &format);
    SGTimePitch *shifter = SGTimePitchCreate(kRate, 2, NULL, NULL);
    SGTimePitchSetSemitones(shifter, semitones);
    float left[1024], right[1024];
    size_t seconds = 0;
    for (;;) {
        struct { AudioBufferList list; AudioBuffer second; } buffers = {{2, {{1, sizeof left, left}}}, {1, sizeof right, right}};
        UInt32 frames = 1024;
        if (ExtAudioFileRead(file, &frames, &buffers.list) || !frames) break;
        float *channels[2] = {left, right};
        SGTimePitchProcess(shifter, channels, frames);
        buffers.list.mBuffers[0].mDataByteSize = buffers.second.mDataByteSize = frames * 4;
        ExtAudioFileWrite(output, frames, &buffers.list);
        seconds += frames;
        if (seconds > kRate * 40) break;
    }
    ExtAudioFileDispose(file);
    ExtAudioFileDispose(output);
    printf("wrote %s (%+.0f st), underruns %u\n", outPath.UTF8String, semitones, SGTimePitchUnderruns(shifter));
}

typedef struct { double phase; } Sine;

static OSStatus sineSource(void *context, UInt32 frames, AudioBufferList *data) {
    Sine *sine = context;
    for (UInt32 i = 0; i < frames; i++) {
        float value = 0.5f * sinf(2 * M_PI * 440 * (sine->phase + i) / kRate);
        for (UInt32 c = 0; c < data->mNumberBuffers; c++) ((float *)data->mBuffers[c].mData)[i] = value;
    }
    sine->phase += frames;
    return noErr;
}

// What of the steady part is not a sine at `hz`, in dB under it: a least squares fit of the sine and
// the cosine at that frequency, and the residual's energy against theirs.
static double residualAt(const float *samples, size_t count, double hz) {
    double ss = 0, sc = 0, cc = 0, ys = 0, yc = 0;
    for (size_t i = 0; i < count; i++) {
        double s = sin(2 * M_PI * hz * i / kRate), c = cos(2 * M_PI * hz * i / kRate);
        ss += s * s; sc += s * c; cc += c * c; ys += samples[i] * s; yc += samples[i] * c;
    }
    double det = ss * cc - sc * sc, a = (ys * cc - yc * sc) / det, b = (yc * ss - ys * sc) / det;
    double signal = 0, rest = 0;
    for (size_t i = 0; i < count; i++) {
        double fit = a * sin(2 * M_PI * hz * i / kRate) + b * cos(2 * M_PI * hz * i / kRate);
        signal += fit * fit;
        rest += (samples[i] - fit) * (samples[i] - fit);
    }
    return 10 * log10(rest / signal);
}

// The same at the frequency that fits best near `hz`: the zero crossings are only good to a tenth of a
// hertz, and over two seconds that much off reads as noise.
static double residual(const float *samples, size_t count, double hz) {
    double best = residualAt(samples, count, hz), center = hz;
    for (double span = 0.4; span > 0.0005; span /= 10) {
        double from = center;
        for (int i = -10; i <= 10; i++) {
            double value = residualAt(samples, count, from + i * span / 10);
            if (value < best) best = value, center = from + i * span / 10;
        }
    }
    return best;
}

// Pull mode at `rate`: the time and pitch unit moved `semitones`, or the varispeed, whose pitch is the rate's.
static void runPull(float rate, float semitones, bool varispeed, UInt32 slice) {
    Sine sine = {0};
    SGTimePitch *unit = varispeed ? SGTimePitchCreateVarispeed(kRate, 2, sineSource, &sine) : SGTimePitchCreate(kRate, 2, sineSource, &sine);
    if (!unit) {
        printf("no unit\n");
        exit(1);
    }
    SGTimePitchSetRate(unit, rate);
    SGTimePitchSetSemitones(unit, semitones);
    size_t total = (size_t)(kRate * 4);
    float *left = calloc(total, sizeof(float)), *right = calloc(total, sizeof(float));
    for (size_t done = 0; done + slice <= total; done += slice) {
        struct { AudioBufferList list; AudioBuffer second; } buffers = {{2, {{1, slice * 4, left + done}}}, {1, slice * 4, right + done}};
        if (SGTimePitchRender(unit, slice, &buffers.list) != noErr) printf("  render failed\n");
    }
    double measured = frequency(left + (size_t)kRate, total - (size_t)kRate);
    double expected = 440 * (varispeed ? rate : pow(2, semitones / 12));
    double consumedRate = (double)SGTimePitchConsumed(unit) / total;
    printf("pull %-9s rate %.2f %+6.2f st, slices %4u: %6.1f Hz (want %6.1f, %+.2f%%), consumed %.3fx, residual %6.1f dB, delay %4zu frames (unit %.1f ms), largest pull %u, failures %u\n",
           varispeed ? "varispeed" : "timepitch", rate, varispeed ? 12 * log2(rate) : semitones, slice, measured, expected, (measured / expected - 1) * 100,
           consumedRate, residual(left + (size_t)kRate, (size_t)kRate * 2, measured), onset(left, total), SGTimePitchLatency(unit) * 1000,
           SGTimePitchLargestPull(unit), SGTimePitchFailures(unit));
    free(left);
    free(right);
}

// Clicks, one every 250 ms of input: a drum's attack, which a time stretch smears and a varispeed does not.
typedef struct { uint64_t frame; } Clicks;

static OSStatus clickSource(void *context, UInt32 frames, AudioBufferList *data) {
    Clicks *clicks = context;
    for (UInt32 i = 0; i < frames; i++) {
        float value = (clicks->frame + i) % (uint64_t)(kRate / 4) == 0 ? 0.9f : 0;
        for (UInt32 c = 0; c < data->mNumberBuffers; c++) ((float *)data->mBuffers[c].mData)[i] = value;
    }
    clicks->frame += frames;
    return noErr;
}

// How much of each click's energy stays within 2 ms of its peak, of what lands within 60 ms of it,
// averaged over the clicks after the first second: 100% is a click as sharp as it went in.
static void runClicks(float rate, float semitones, bool varispeed) {
    Clicks clicks = {0};
    SGTimePitch *unit = varispeed ? SGTimePitchCreateVarispeed(kRate, 2, clickSource, &clicks) : SGTimePitchCreate(kRate, 2, clickSource, &clicks);
    SGTimePitchSetRate(unit, rate);
    SGTimePitchSetSemitones(unit, semitones);
    size_t total = (size_t)(kRate * 6);
    float *left = calloc(total, sizeof(float)), *right = calloc(total, sizeof(float));
    for (size_t done = 0; done + 1024 <= total; done += 1024) {
        struct { AudioBufferList list; AudioBuffer second; } buffers = {{2, {{1, 4096, left + done}}}, {1, 4096, right + done}};
        SGTimePitchRender(unit, 1024, &buffers.list);
    }
    size_t spacing = (size_t)(kRate / 4 / rate), near = (size_t)(kRate * 0.002), wide = (size_t)(kRate * 0.06);
    double sharp = 0;
    int counted = 0;
    for (size_t from = (size_t)kRate; from + spacing < total - wide; from += spacing) {
        size_t peak = from;
        for (size_t i = from; i < from + spacing; i++) if (fabsf(left[i]) > fabsf(left[peak])) peak = i;
        if (peak < wide || peak + wide >= total) continue;
        double inNear = 0, inWide = 0;
        for (size_t i = peak - wide; i < peak + wide; i++) {
            double energy = (double)left[i] * left[i];
            inWide += energy;
            if (i + near >= peak && i <= peak + near) inNear += energy;
        }
        if (inWide > 0) sharp += inNear / inWide, counted++;
    }
    printf("clicks %-9s rate %.2f %+6.2f st: %5.1f%% of each click within 2 ms of its peak (%d clicks)\n",
           varispeed ? "varispeed" : "timepitch", rate, varispeed ? 12 * log2(rate) : semitones, counted ? sharp / counted * 100 : 0, counted);
    free(left);
    free(right);
}

typedef struct { ExtAudioFileRef file; } SongSource;

static OSStatus songSource(void *context, UInt32 frames, AudioBufferList *data) {
    SongSource *song = context;
    UInt32 read = frames;
    for (UInt32 c = 0; c < data->mNumberBuffers; c++) data->mBuffers[c].mDataByteSize = frames * 4;
    if (ExtAudioFileRead(song->file, &read, data) || read < frames) {
        for (UInt32 c = 0; c < data->mNumberBuffers; c++) memset((float *)data->mBuffers[c].mData + read, 0, (frames - read) * 4);
    }
    return noErr;
}

// The song played at `rate` through the chain's way of doing it, into a file to listen to.
static void runSongPull(NSString *path, float rate, float semitones, bool varispeed, NSString *outPath) {
    SongSource song;
    if (ExtAudioFileOpenURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], &song.file)) return;
    AudioStreamBasicDescription format = {
        .mSampleRate = kRate, .mFormatID = kAudioFormatLinearPCM,
        .mFormatFlags = kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
        .mBytesPerPacket = 4, .mFramesPerPacket = 1, .mBytesPerFrame = 4, .mChannelsPerFrame = 2, .mBitsPerChannel = 32,
    };
    ExtAudioFileSetProperty(song.file, kExtAudioFileProperty_ClientDataFormat, sizeof format, &format);
    ExtAudioFileRef output;
    AudioStreamBasicDescription wav = {
        .mSampleRate = kRate, .mFormatID = kAudioFormatLinearPCM,
        .mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
        .mBytesPerPacket = 4, .mFramesPerPacket = 1, .mBytesPerFrame = 4, .mChannelsPerFrame = 2, .mBitsPerChannel = 16,
    };
    ExtAudioFileCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:outPath], kAudioFileWAVEType, &wav, NULL, kAudioFileFlags_EraseFile, &output);
    ExtAudioFileSetProperty(output, kExtAudioFileProperty_ClientDataFormat, sizeof format, &format);
    SGTimePitch *unit = varispeed ? SGTimePitchCreateVarispeed(kRate, 2, songSource, &song) : SGTimePitchCreate(kRate, 2, songSource, &song);
    SGTimePitchSetRate(unit, rate);
    SGTimePitchSetSemitones(unit, semitones);
    static float left[4096], right[4096];
    for (size_t done = 0; done < kRate * 30; done += 4096) {
        struct { AudioBufferList list; AudioBuffer second; } buffers = {{2, {{1, sizeof left, left}}}, {1, sizeof right, right}};
        SGTimePitchRender(unit, 4096, &buffers.list);
        ExtAudioFileWrite(output, 4096, &buffers.list);
    }
    ExtAudioFileDispose(song.file);
    ExtAudioFileDispose(output);
    printf("wrote %s\n", outPath.UTF8String);
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        for (int pattern = 0; pattern < 3; pattern++) {
            for (NSNumber *semitones in @[@-12, @-5, @-1, @0.5, @3, @7, @12]) runSine(semitones.floatValue, pattern);
        }
        for (NSNumber *rate in @[@0.5, @0.75, @1, @1.25, @1.5, @2]) {
            runPull(rate.floatValue, 0, false, 1024);
            runPull(rate.floatValue, 3, false, 1024);
            // Pitch going with speed: the old sliders' nearest whole semitone, the exact one, and the varispeed.
            float follows = 12 * log2f(rate.floatValue);
            runPull(rate.floatValue, roundf(follows), false, 1024);
            runPull(rate.floatValue, follows, false, 1024);
            runPull(rate.floatValue, 0, true, 1024);
            runPull(rate.floatValue, 0, true, 4096);
        }
        for (NSNumber *rate in @[@0.75, @1, @1.25, @1.5]) {
            runClicks(rate.floatValue, 0, false);
            runClicks(rate.floatValue, 12 * log2f(rate.floatValue), false);
            runClicks(rate.floatValue, 0, true);
        }
        if (argc > 1) {
            NSString *song = @(argv[1]);
            runSong(song, 3, @"build/song+3.wav");
            runSong(song, -4, @"build/song-4.wav");
            runSongPull(song, 1.25f, 4, false, @"build/song-1.25x+4st.wav");
            runSongPull(song, 1.25f, 0, true, @"build/song-1.25x-varispeed.wav");
        }
    }
    return 0;
}
