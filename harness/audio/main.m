// Deterministic graph-control tests for the production pipeline. The Core Audio boundary is mocked;
// harness/speed, harness/audio-effects/sim and harness/haptics/sim cover real RemoteIO rendering.
#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "Shared/Audio/SGAudioSourceQueue.h"
#import <assert.h>
#import <pthread.h>
#import <stdatomic.h>
#import <unistd.h>

#if TARGET_OS_OSX
#define kAudioUnitSubType_RemoteIO 'rioc'
#endif

typedef struct {
    bool output, disposed;
    UInt32 limit;
    AudioStreamBasicDescription format;
    AURenderCallbackStruct callback;
    AudioUnitConnection connection;
    unsigned renders;
    UInt32 lastBus, frames;
    double lastTime;
} Unit;
static AudioUnit unit(Unit *value) { return (AudioUnit)value; }
static Unit *mock(AudioUnit value) { return (Unit *)value; }
static atomic_bool blockRender, renderEntered, releaseRender;
static OSStatus renderError;
static bool renderSilence, refuseCallback;
static bool reentrantChange;
static uint64_t naturalBoundary = UINT64_MAX;
static OSStatus (*reboundSet)(AudioUnit, AudioUnitPropertyID, AudioUnitScope, AudioUnitElement, const void *, UInt32);

AudioComponent AudioComponentInstanceGetComponent(AudioComponentInstance instance) { return (AudioComponent)instance; }
OSStatus AudioComponentGetDescription(AudioComponent component, AudioComponentDescription *description) {
    *description = (AudioComponentDescription){mock((AudioUnit)component)->output ? kAudioUnitType_Output : kAudioUnitType_Mixer,
        kAudioUnitSubType_RemoteIO, kAudioUnitManufacturer_Apple, 0, 0};
    return noErr;
}
OSStatus AudioUnitGetProperty(AudioUnit value, AudioUnitPropertyID property, AudioUnitScope scope, AudioUnitElement element,
                             void *data, UInt32 *size) {
    if (property == kAudioUnitProperty_StreamFormat) memcpy(data, &mock(value)->format, *size);
    else if (property == kAudioUnitProperty_MaximumFramesPerSlice) *(UInt32 *)data = mock(value)->limit;
    else return kAudioUnitErr_InvalidProperty;
    return noErr;
}
OSStatus AudioUnitRender(AudioUnit value, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *time,
                        UInt32 bus, UInt32 frames, AudioBufferList *data) {
    Unit *u = mock(value);
    assert(!u->disposed && frames <= u->limit);
    if (reentrantChange) {
        UInt32 limit = 512;
        assert(reboundSet(value, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0,
                          &limit, sizeof limit) == kAudioUnitErr_CannotDoInCurrentContext);
        reentrantChange = false;
    }
    if (atomic_load(&blockRender)) {
        atomic_store(&renderEntered, true);
        while (!atomic_load(&releaseRender)) usleep(100);
    }
    u->renders++; u->lastBus = bus; u->lastTime = time->mSampleTime; u->frames += frames;
    if (renderError) return renderError;
    if (renderSilence) { *flags |= kAudioUnitRenderAction_OutputIsSilence; return noErr; }
    for (UInt32 b = 0; b < data->mNumberBuffers; b++)
        for (UInt32 n = 0; n < frames; n++)
            ((float *)data->mBuffers[b].mData)[n] = u->frames - frames + n >= naturalBoundary ? .45f : .25f;
    return noErr;
}
OSStatus AudioUnitAddRenderNotify(AudioUnit u, AURenderCallback callback, void *context) { return noErr; }
OSStatus AudioUnitRemoveRenderNotify(AudioUnit u, AURenderCallback callback, void *context) { return noErr; }
OSStatus AudioUnitAddPropertyListener(AudioUnit u, AudioUnitPropertyID property, AudioUnitPropertyListenerProc listener, void *context) { return noErr; }
OSStatus AudioUnitRemovePropertyListenerWithUserData(AudioUnit u, AudioUnitPropertyID property, AudioUnitPropertyListenerProc listener, void *context) { return noErr; }

static OSStatus mockSet(AudioUnit value, AudioUnitPropertyID property, AudioUnitScope scope, AudioUnitElement element,
                        const void *data, UInt32 size) {
    if (property == kAudioUnitProperty_SetRenderCallback) {
        if (refuseCallback && ((const AURenderCallbackStruct *)data)->inputProc) return kAudioUnitErr_InvalidProperty;
        mock(value)->callback = *(const AURenderCallbackStruct *)data;
    } else if (property == kAudioUnitProperty_MakeConnection) mock(value)->connection = *(const AudioUnitConnection *)data;
    else if (property == kAudioUnitProperty_MaximumFramesPerSlice) mock(value)->limit = *(const UInt32 *)data;
    return noErr;
}
static OSStatus mockStart(AudioUnit value) { return noErr; }
static OSStatus mockDispose(AudioComponentInstance value) { mock(value)->disposed = true; return noErr; }
BOOL SGRebindImport(const char *symbol, void *replacement, void **original) {
    if (!strcmp(symbol, "AudioUnitSetProperty")) { *original = mockSet; reboundSet = replacement; }
    else if (!strcmp(symbol, "AudioOutputUnitStart")) *original = mockStart;
    else if (!strcmp(symbol, "AudioComponentInstanceDispose")) *original = mockDispose;
    else return NO;
    return YES;
}

// Decoder metadata is a separate guarded-reader test. Here control the spare PCM budget.
static OSStatus nativeSource(void *c, AudioUnitRenderActionFlags *f, const AudioTimeStamp *t,
                             UInt32 b, UInt32 n, AudioBufferList *d) { return noErr; }
void SGAudioSourceQueueInitialize(void) {}
bool SGAudioSourceQueueSupported(AURenderCallbackStruct callback) { return callback.inputProc == nativeSource; }
UInt32 SGAudioSourceQueueFrames(AURenderCallbackStruct callback, UInt32 maximumFrames) { return SGAudioSourceQueueSupported(callback) ? MIN(44100, maximumFrames) : 0; }
SGAudioSourcePrefix SGAudioSourceQueuePrefix(AURenderCallbackStruct callback, UInt32 maximumFrames, bool continuous) {
    UInt32 frames = SGAudioSourceQueueFrames(callback, maximumFrames);
    uint64_t at = ((Unit *)callback.inputProcRefCon)->frames;
    uint64_t boundary = naturalBoundary >= at ? naturalBoundary - at : UINT64_MAX;
    if (!continuous && boundary < frames) frames = (UInt32)boundary;
    return (SGAudioSourcePrefix){frames, continuous && boundary < frames ? (UInt32)boundary : UINT32_MAX};
}

#include "Shared/Audio/SGAudioPipeline.x"
#include "Shared/Sing/SGSingAudio.h"

static unsigned stageCalls, stageSequence;
static OSStatus speed(void *c, AudioUnitRenderActionFlags *f, const AudioTimeStamp *t, UInt32 b, UInt32 n, AudioBufferList *d) {
    stageCalls++; stageSequence = stageSequence * 10 + 1; ((float *)d->mBuffers[0].mData)[0] += 1; return noErr;
}
static OSStatus effects(void *c, AudioUnitRenderActionFlags *f, const AudioTimeStamp *t, UInt32 b, UInt32 n, AudioBufferList *d) {
    stageCalls++; stageSequence = stageSequence * 10 + 2; ((float *)d->mBuffers[0].mData)[0] *= 2; return noErr;
}
static OSStatus haptics(void *c, AudioUnitRenderActionFlags *f, const AudioTimeStamp *t, UInt32 b, UInt32 n, AudioBufferList *d) {
    stageCalls++; stageSequence = stageSequence * 10 + 3; assert(((float *)d->mBuffers[0].mData)[0] == 2.5f); return noErr;
}
static void connect(Unit *source, Unit *output, UInt32 bus) {
    AudioUnitConnection connection = {unit(source), bus, 0};
    assert(setProperty(unit(output), kAudioUnitProperty_MakeConnection, kAudioUnitScope_Input, 0, &connection, sizeof connection) == noErr);
}
static float pcm[2][1024];
static struct { AudioBufferList list; AudioBuffer more; } buffers;
static OSStatus render(Unit *output, UInt32 frames) {
    buffers.list.mNumberBuffers = 2;
    for (unsigned i = 0; i < 2; i++) buffers.list.mBuffers[i] = (AudioBuffer){1, frames * sizeof(float), pcm[i]};
    AudioUnitRenderActionFlags flags = 0;
    return feed(unit(output), &flags, NULL, 0, frames, &buffers.list);
}
static bool handledError(UInt32 frames, AudioBufferList *data, OSStatus *status) {
    *status = SGAudioPipelinePull(frames, data, NULL);
    return true;
}
static OSStatus separate(void *context, UInt32 frames, AudioBufferList *data, const AudioTimeStamp *time) {
    assert(context == &stageCalls);
    assert(!SGAudioPipelineSetSourceProcessor(NULL, NULL)); // no graph waits from the render thread
    OSStatus error = SGAudioPipelinePullOriginal(frames, data, time);
    if (!error) for (UInt32 b = 0; b < data->mNumberBuffers; b++)
        for (UInt32 n = 0; n < frames; n++) ((float *)data->mBuffers[b].mData)[n] *= .5f;
    return error;
}
static void *renderThread(void *context) { assert(render(context, 128) == noErr); return NULL; }
static void *disposeThread(void *context) { assert(dispose(unit(context)) == noErr); return NULL; }

static atomic_bool clockReading;
static atomic_uint clockReads;
static void *clockReader(void *context) {
    while (atomic_load(&clockReading)) {
        double position;
        if (SGSingAudioClock(31, &position)) {
            assert(position >= 1000 && position < 1020);
            atomic_fetch_add(&clockReads, 1);
        }
        if (SGSingAudioClock(32, &position)) {
            assert(position >= 0 && position < 10);
            atomic_fetch_add(&clockReads, 1);
        }
    }
    return NULL;
}

static void transition(Unit *source, Unit *output) {
    SGSingAudio *audio = SGSingAudioCreate((SGAudioStamp){7, 31, 0, 3, 0}, 88200, 66150, .2f);
    SGSingAudioSetClock(audio, 1000, 31); SGSingAudioExpectTrack(audio, 32);
    assert(SGSingAudioAttach(audio));
    atomic_store(&clockReading, true);
    pthread_t reader;
    assert(!pthread_create(&reader, NULL, clockReader, NULL));
    SGSingStream *s = SGSingAudioStream(audio);
    const uint64_t boundary = 10 * 44100 + 137; // deliberately inside an irregular render quantum
    naturalBoundary = source->frames + boundary;
    float input[2048];
    static float vocal[132300];
    for (unsigned i = 0; i < 132300; i++) vocal[i] = .1f;
    uint64_t captured = 0, nextWindow = 0, audible = 0;
    bool continued = false;
    for (unsigned tick = 0; tick < 800; tick++) {
        unsigned frames = tick % 3 ? 882 : 471;
        assert(!render(output, frames));
        if (tick > 300) for (unsigned n = 0; n < frames; n++) {
            float expected = (audible + n >= boundary ? .45f : .25f) - .096f;
            assert(fabsf(pcm[0][n] - expected) < 1e-6 && pcm[0][n] == pcm[1][n]);
        }
        audible += frames;
        SGAudioStamp packet;
        while (SGSingStreamReadInput(s, &packet, input)) {
            assert(packet.sourceFrame == captured);
            captured += packet.frames;
        }
        while (captured >= nextWindow + 88200) {
            assert(SGSingStreamWriteVocals(s, (SGAudioStamp){7,31,nextWindow,3,66150}, vocal));
            nextWindow += 66150;
        }
        if (!continued && captured > boundary) {
            assert(!SGSingAudioContinueTrack(audio, 99)); // changed queue identity cannot reuse stems
            assert(SGSingAudioContinueTrack(audio, 32));
            assert(SGSingAudioAwaitingTrack(audio, 32) && audible < boundary);
            continued = true;
        }
        double position = -1;
        uint64_t track = audible < boundary ? 31 : 32;
        assert(SGSingAudioClock(track, &position));
        double expectedPosition = audible < boundary ? 1000 + audible / 44100.0 : (audible - boundary) / 44100.0;
        assert(fabs(position - expectedPosition) < 1e-6);
        if (tick > 300) assert(SGSingStreamState(s) == SGSingTimelineActive);
    }
    atomic_store(&clockReading, false);
    pthread_join(reader, NULL);
    assert(atomic_load(&clockReads));
    assert(continued && !SGSingAudioAwaitingTrack(audio, 32));
    SGSingAudioInvalidate(); assert(!SGSingAudioContinueTrack(audio, 32));
    SGSingAudioDetach(audio); SGSingAudioDestroy(audio); naturalBoundary = UINT64_MAX;
}

int main(void) {
    @autoreleasepool {
        static const SGAudioProcessor a = {NULL, speed}, b = {NULL, effects}, c = {NULL, haptics};
        assert(SGAudioPipelineRegister(SGAudioStageHaptics, &c));
        assert(SGAudioPipelineRegister(SGAudioStageSpeedPitch, &a));
        assert(SGAudioPipelineRegister(SGAudioStageEffects, &b));
        AudioStreamBasicDescription format = {44100, kAudioFormatLinearPCM,
            kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved, 4, 1, 4, 2, 32, 0};
        Unit unrelated[12] = {0};
        AURenderCallbackStruct other = {feed, NULL};
        for (unsigned i = 0; i < 12; i++)
            assert(!setProperty(unit(&unrelated[i]), kAudioUnitProperty_SetRenderCallback,
                kAudioUnitScope_Input, 0, &other, sizeof other));
        Unit source = {.format = format, .limit = 256}, output = {.output = true, .format = format, .limit = 1024};
        AURenderCallbackStruct native = {nativeSource, &source};
        assert(!setProperty(unit(&source), kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &native, sizeof native));
        connect(&source, &output, 7);
        assert(SGAudioPipelineSourceCanReadAhead());
        assert(SGAudioPipelineSourceAheadFrames(44100) == 0); // never expose queue metadata off-render
        assert(SGAudioPipelineTapped());
        start(unit(&output));
        reentrantChange = true;
        assert(render(&output, 700) == noErr && source.renders == 3 && source.frames == 700 && source.lastBus == 7 && source.lastTime == 512);
        assert(render(&output, 128) == noErr && source.lastTime == 700);
        AudioUnitRenderActionFlags flags = kAudioUnitRenderAction_PostRender;
        rendered(unit(&output), &flags, NULL, 0, 128, &buffers.list);
        assert(stageSequence == 123 && stageCalls == 3);
        flags |= kAudioUnitRenderAction_PostRenderError;
        rendered(unit(&output), &flags, NULL, 0, 128, &buffers.list);
        assert(stageCalls == 3);
        renderSilence = true;
        assert(render(&output, 128) == noErr && pcm[0][0] == 0);
        renderSilence = false;
        assert(SGAudioPipelineSetSourceProcessor(separate, &stageCalls));
        assert(render(&output, 128) == noErr && pcm[0][0] == .125f);
        SGAudioPipelineSetPullProcessor(handledError); // speed/pitch also receives separated input
        assert(render(&output, 128) == noErr && pcm[0][0] == .125f);
        assert(SGAudioPipelineSetSourceProcessor(NULL, NULL));
        SGSingAudio *sing = SGSingAudioCreate((SGAudioStamp){1, 2, 0, 3, 0}, 88200, 44100, 0);
        assert(sing); SGSingAudioSetClock(sing, 12.0, 2);
        assert(SGSingAudioAttach(sing));
        double audible;
        SGSingStream *stream = SGSingAudioStream(sing);
        float input[2048];
        static float vocal[88200];
        SGAudioStamp packet;
        uint64_t captured = 0, nextWindow = 0;
        for (unsigned i = 0; i < 88200; i++) vocal[i] = .1f;
        for (unsigned i = 0; i < 220; i++) {
            assert(render(&output, 882) == noErr);
            if (i < 100) assert(pcm[0][0] == .25f); // no preparation silence
            while (SGSingStreamReadInput(stream, &packet, input)) {
                assert(packet.sourceFrame == captured && input[0] == .25f);
                captured += packet.frames;
            }
            while (captured >= nextWindow + 88200) {
                assert(SGSingStreamWriteVocals(stream, (SGAudioStamp){1,2,nextWindow,3,44100}, vocal));
                nextWindow += 44100;
            }
            assert(SGSingAudioClock(2, &audible) && fabs(audible - (12.0 + (i+1)*.02)) < 1e-6);
            assert(!SGSingAudioClock(9, &audible));
        }
        assert(SGSingStreamState(stream) == SGSingTimelineActive);
        assert(fabsf(pcm[0][0] - .154f) < 1e-6); // 20% perceptual vocal gain
        SGSingStreamBypass(stream);
        for (unsigned i = 0; i < 260; i++) {
            assert(render(&output, 882) == noErr);
            if (i > 6) assert(pcm[0][0] == .25f);
        }
        assert(SGSingStreamState(stream) == SGSingTimelineIdle);
        assert(SGSingAudioClock(2, &audible) && fabs(audible - 21.6) < 1e-6);
        SGSingAudioInvalidate();
        unsigned stalePulls = source.renders;
        uint64_t staleFrames = source.frames;
        assert(render(&output, 882) == noErr && pcm[0][0] == .25f && source.renders > stalePulls);
        assert(source.frames == staleFrames + 882); // new original source continues during the handoff
        assert(!SGSingAudioClock(2, &audible));
        SGSingAudioDetach(sing);
        SGSingAudioDestroy(sing);
        transition(&source, &output);
        assert(SGAudioPipelineSetSourceProcessor(separate, &stageCalls));
        assert(!setProperty(unit(&source), kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &other, sizeof other));
        assert(!SGAudioPipelineSourceProcessorAttached(&stageCalls) && !SGAudioPipelineSourceCanReadAhead());
        assert(!setProperty(unit(&source), kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &native, sizeof native));
        assert(SGAudioPipelineSourceCanReadAhead());
        SGAudioPipelineSetPullProcessor(handledError);
        renderError = -123;
        unsigned before = source.renders;
        assert(render(&output, 128) == -123 && source.renders == before + 1);
        renderError = 0;
        SGAudioPipelineSetPullProcessor(NULL);
        assert(SGAudioPipelinePull(128, &buffers.list, NULL) == kAudioUnitErr_NoConnection);
        Unit another = {.output = true, .format = format, .limit = 1024};
        start(unit(&another));
        assert(!SGAudioPipelineTapped());
        before = source.renders;
        assert(render(&output, 128) == noErr && source.renders == before && pcm[0][0] == 0);
        connect(&source, &output, 3);
        AURenderCallbackStruct own = {NULL, NULL};
        setProperty(unit(&output), kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &own, sizeof own);
        assert(!SGAudioPipelineTapped());
        connect(&source, &output, 3);
        source.format.mFormatFlags = 0;
        connect(&source, &output, 4);
        assert(!SGAudioPipelineTapped() && output.callback.inputProc == NULL && output.connection.sourceOutputNumber == 4);
        source.format = format;
        refuseCallback = true;
        connect(&source, &output, 5);
        assert(!SGAudioPipelineTapped() && output.callback.inputProc == NULL && output.connection.sourceOutputNumber == 5);
        refuseCallback = false;
        connect(&source, &output, 6);
        output.format.mSampleRate = 48000;
        start(unit(&output));
        assert(!SGAudioPipelineTapped() && output.callback.inputProc == NULL);
        output.format = format;
        connect(&source, &output, 6);
        atomic_store(&blockRender, true);
        pthread_t reader, disposer;
        pthread_create(&reader, NULL, renderThread, &output);
        while (!atomic_load(&renderEntered)) usleep(100);
        pthread_create(&disposer, NULL, disposeThread, &source);
        while (!(atomic_load(&gate) & changing)) usleep(100);
        assert(!source.disposed);
        atomic_store(&releaseRender, true);
        pthread_join(reader, NULL); pthread_join(disposer, NULL);
        assert(source.disposed && !SGAudioPipelineTapped());
        assert(render(&output, 128) == noErr && pcm[0][0] == 0);
        dispose(unit(&output));
        assert(atomic_load(&outputUnit) == NULL);
        puts("audio pipeline: ordering, chunking, errors, replacement, formats and concurrent disposal passed");
    }
}
