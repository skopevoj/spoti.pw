#import "SGTimePitch.h"
#import <stdatomic.h>
#import <stdlib.h>
#import <string.h>

// The FIFO of in place mode, a power of two with room for a few of the largest buffers.
enum { kFifoFrames = 16384 };

struct SGTimePitch {
    AudioUnit unit;
    bool varispeed;
    double sampleRate;
    UInt32 channels;
    SGTimePitchSource source;
    void *context;
    float *fifo[kSGTimePitchMaxChannels];
    uint64_t written, read;           // render thread only
    Float64 sampleTime;
    struct {
        AudioBufferList list;
        AudioBuffer more[kSGTimePitchMaxChannels - 1];
    } output;
    float *outputData[kSGTimePitchMaxChannels];
    atomic_uint underruns, failures, largestPull;
    atomic_uint_fast64_t consumed;
    double latency;
};

static OSStatus input(void *refCon, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *timestamp, UInt32 bus,
                      UInt32 frames, AudioBufferList *data) {
    SGTimePitch *unit = refCon;
    if (frames > atomic_load_explicit(&unit->largestPull, memory_order_relaxed)) {
        atomic_store_explicit(&unit->largestPull, frames, memory_order_relaxed);
    }
    atomic_fetch_add_explicit(&unit->consumed, frames, memory_order_relaxed);
    if (unit->source) return unit->source(unit->context, frames, data);

    uint64_t available = unit->written - unit->read;
    UInt32 served = (UInt32)(available < frames ? available : frames);
    if (served < frames) atomic_fetch_add_explicit(&unit->underruns, 1, memory_order_relaxed);
    for (UInt32 c = 0; c < data->mNumberBuffers && c < unit->channels; c++) {
        float *out = data->mBuffers[c].mData;
        if (!out) continue;
        for (UInt32 i = 0; i < served; i++) out[i] = unit->fifo[c][(unit->read + i) & (kFifoFrames - 1)];
        if (served < frames) memset(out + served, 0, (frames - served) * sizeof(float));
        data->mBuffers[c].mDataByteSize = frames * sizeof(float);
    }
    unit->read += served;
    return noErr;
}

static SGTimePitch *create(bool varispeed, double sampleRate, UInt32 channels, SGTimePitchSource source, void *context) {
    if (sampleRate <= 0 || channels < 1 || channels > kSGTimePitchMaxChannels) return NULL;
    AudioComponentDescription description = {
        .componentType = kAudioUnitType_FormatConverter,
        .componentSubType = varispeed ? kAudioUnitSubType_Varispeed : kAudioUnitSubType_NewTimePitch,
        .componentManufacturer = kAudioUnitManufacturer_Apple,
    };
    AudioComponent component = AudioComponentFindNext(NULL, &description);
    if (!component) return NULL;
    SGTimePitch *unit = calloc(1, sizeof *unit);
    if (!unit) return NULL;
    unit->varispeed = varispeed;
    unit->sampleRate = sampleRate;
    unit->channels = channels;
    unit->source = source;
    unit->context = context;
    if (AudioComponentInstanceNew(component, &unit->unit) != noErr) {
        free(unit);
        return NULL;
    }
    AudioStreamBasicDescription format = {
        .mSampleRate = sampleRate,
        .mFormatID = kAudioFormatLinearPCM,
        .mFormatFlags = kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
        .mBytesPerPacket = sizeof(float),
        .mFramesPerPacket = 1,
        .mBytesPerFrame = sizeof(float),
        .mChannelsPerFrame = channels,
        .mBitsPerChannel = 32,
    };
    UInt32 maxFrames = kSGTimePitchMaxFrames;
    AURenderCallbackStruct callback = {input, unit};
    OSStatus status = AudioUnitSetProperty(unit->unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, sizeof format);
    if (!status) status = AudioUnitSetProperty(unit->unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &format, sizeof format);
    if (!status) status = AudioUnitSetProperty(unit->unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFrames, sizeof maxFrames);
    if (!status) status = AudioUnitSetProperty(unit->unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback, sizeof callback);
    if (!status) status = AudioUnitSetParameter(unit->unit, varispeed ? kVarispeedParam_PlaybackRate : kNewTimePitchParam_Rate, kAudioUnitScope_Global, 0, 1, 0);
    if (!status) status = AudioUnitInitialize(unit->unit);
    if (status) {
        AudioComponentInstanceDispose(unit->unit);
        free(unit);
        return NULL;
    }
    Float64 latency = 0;
    UInt32 size = sizeof latency;
    if (AudioUnitGetProperty(unit->unit, kAudioUnitProperty_Latency, kAudioUnitScope_Global, 0, &latency, &size) == noErr) {
        unit->latency = latency;
    }
    unit->output.list.mNumberBuffers = channels;
    for (UInt32 c = 0; c < channels; c++) {
        if (!source) unit->fifo[c] = calloc(kFifoFrames, sizeof(float));
        unit->outputData[c] = calloc(kSGTimePitchMaxFrames, sizeof(float));
    }
    return unit;
}

SGTimePitch *SGTimePitchCreate(double sampleRate, UInt32 channels, SGTimePitchSource source, void *context) {
    return create(false, sampleRate, channels, source, context);
}

SGTimePitch *SGTimePitchCreateVarispeed(double sampleRate, UInt32 channels, SGTimePitchSource source, void *context) {
    return source ? create(true, sampleRate, channels, source, context) : NULL;
}

bool SGTimePitchIsVarispeed(const SGTimePitch *unit) {
    return unit->varispeed;
}

double SGTimePitchSampleRate(const SGTimePitch *unit) {
    return unit->sampleRate;
}

UInt32 SGTimePitchChannels(const SGTimePitch *unit) {
    return unit->channels;
}

void SGTimePitchSetRate(SGTimePitch *unit, float rate) {
    AudioUnitSetParameter(unit->unit, unit->varispeed ? kVarispeedParam_PlaybackRate : kNewTimePitchParam_Rate, kAudioUnitScope_Global, 0, rate, 0);
}

void SGTimePitchSetSemitones(SGTimePitch *unit, float semitones) {
    if (unit->varispeed) return;
    AudioUnitSetParameter(unit->unit, kNewTimePitchParam_Pitch, kAudioUnitScope_Global, 0, semitones * 100, 0);
}

void SGTimePitchReset(SGTimePitch *unit) {
    AudioUnitReset(unit->unit, kAudioUnitScope_Global, 0);
    unit->written = unit->read = 0;
    unit->sampleTime = 0;
}

OSStatus SGTimePitchRender(SGTimePitch *unit, UInt32 frames, AudioBufferList *data) {
    if (!frames || frames > kSGTimePitchMaxFrames) return kAudioUnitErr_TooManyFramesToProcess;
    AudioTimeStamp timestamp = {.mSampleTime = unit->sampleTime, .mFlags = kAudioTimeStampSampleTimeValid};
    AudioUnitRenderActionFlags flags = 0;
    OSStatus status = AudioUnitRender(unit->unit, &flags, &timestamp, 0, frames, data);
    unit->sampleTime += frames;
    if (status != noErr) atomic_fetch_add_explicit(&unit->failures, 1, memory_order_relaxed);
    return status;
}

bool SGTimePitchProcess(SGTimePitch *unit, float *const *channels, UInt32 frames) {
    if (unit->source || !frames || frames > kSGTimePitchMaxFrames) return false;
    // A FIFO that would overflow (the unit stopped pulling) starts over rather than wrap onto itself.
    if (unit->written - unit->read + frames > kFifoFrames) {
        unit->written = unit->read = 0;
        atomic_fetch_add_explicit(&unit->failures, 1, memory_order_relaxed);
        return false;
    }
    for (UInt32 c = 0; c < unit->channels; c++) {
        const float *in = channels[c];
        for (UInt32 i = 0; i < frames; i++) unit->fifo[c][(unit->written + i) & (kFifoFrames - 1)] = in[i];
    }
    unit->written += frames;

    for (UInt32 c = 0; c < unit->channels; c++) {
        unit->output.list.mBuffers[c] = (AudioBuffer){1, frames * (UInt32)sizeof(float), unit->outputData[c]};
    }
    if (SGTimePitchRender(unit, frames, &unit->output.list) != noErr) return false;
    for (UInt32 c = 0; c < unit->channels; c++) {
        const float *out = unit->output.list.mBuffers[c].mData;
        if (out) memcpy(channels[c], out, frames * sizeof(float));
    }
    return true;
}

UInt32 SGTimePitchUnderruns(const SGTimePitch *unit) {
    return atomic_load((atomic_uint *)&unit->underruns);
}

UInt32 SGTimePitchFailures(const SGTimePitch *unit) {
    return atomic_load((atomic_uint *)&unit->failures);
}

double SGTimePitchLatency(const SGTimePitch *unit) {
    return unit->latency;
}

UInt32 SGTimePitchLargestPull(const SGTimePitch *unit) {
    return atomic_load((atomic_uint *)&unit->largestPull);
}

uint64_t SGTimePitchConsumed(const SGTimePitch *unit) {
    return atomic_load((atomic_uint_fast64_t *)&unit->consumed);
}
