#include "SGSingAudio.h"
#include "Shared/Audio/SGAudioPipeline.h"
#include <stdlib.h>
#include <stdatomic.h>
#include <string.h>
#include <math.h>

static _Atomic uint64_t epoch = 1, clockEpoch, clockTrack, clockBits, clockSequence;
static uint64_t bitsOf(double value) { uint64_t bits; memcpy(&bits, &value, sizeof bits); return bits; }
static double valueOf(uint64_t bits) { double value; memcpy(&value, &bits, sizeof value); return value; }
struct SGSingAudio {
    uint64_t epoch, track, origin;
    double position;
    _Atomic uint64_t latencyBits;
    _Atomic uint64_t expectedTrack, prefetchedTrack, prefetchedFrame;
    uint64_t lastBoundary;
    // Main produces clock markers, render consumes them when their PCM becomes audible.
    struct { uint64_t track, frame; } markers[4];
    atomic_uint markerHead, markerTail;
    SGSingStream *stream;
    const AudioTimeStamp *time; // borrowed only within the current render call
    float planar[2][SGSingStreamMaximumRenderFrames];
    float mixed[2 * SGSingStreamMaximumRenderFrames];
};
static int32_t pullOriginal(void *context, uint32_t frames, float *stereo) {
    SGSingAudio *a = context;
    struct { AudioBufferList list; AudioBuffer more; } data;
    data.list.mNumberBuffers = 2;
    for (unsigned c = 0; c < 2; c++) data.list.mBuffers[c] = (AudioBuffer){1, frames * sizeof(float), a->planar[c]};
    OSStatus error = SGAudioPipelinePullOriginal(frames, &data.list, a->time);
    if (!error) for (uint32_t n = 0; n < frames; n++)
        for (unsigned c = 0; c < 2; c++) stereo[n*2+c] = a->planar[c][n];
    return error;
}
static OSStatus process(void *context, UInt32 frames, AudioBufferList *data, const AudioTimeStamp *time) {
    SGSingAudio *a = context;
    if (!data || data->mNumberBuffers != 2 || frames > UINT32_MAX / sizeof(float)) return kAudio_ParamError;
    for (unsigned c = 0; c < 2; c++)
        if (!data->mBuffers[c].mData || data->mBuffers[c].mNumberChannels != 1 || data->mBuffers[c].mDataByteSize < frames*sizeof(float))
            return kAudio_ParamError;
    if (a->epoch != atomic_load(&epoch)) {
        // A seek/skip has invalidated the old stems but main has not detached us yet. Follow
        // Spotify's current source during that interval, rather than muting its new audio.
        return SGAudioPipelinePullOriginal(frames, data, time);
    }
    a->time = time;
    for (UInt32 done = 0; done < frames;) {
        UInt32 count = MIN(frames - done, SGSingStreamMaximumRenderFrames);
        // The stream pulls at most two quanta and leaves 120 ms in Spotify's queue.
        // Counting any further ahead adds kernel reads to every audio callback for no gain.
        uint64_t captured = SGSingStreamCaptured(a->stream);
        uint64_t expected = atomic_load(&a->expectedTrack), prefetched = atomic_load(&a->prefetchedTrack);
        bool continuous = expected && (!prefetched || captured <= atomic_load(&a->prefetchedFrame));
        SGAudioSourcePrefix prefix = SGAudioPipelineSourcePrefix(count * 2 + 5292, continuous);
        if (prefix.boundary != UINT32_MAX && captured + prefix.boundary != a->lastBoundary && !prefetched) {
            a->lastBoundary = captured + prefix.boundary;
            atomic_store(&a->prefetchedFrame, a->lastBoundary);
            atomic_store(&a->prefetchedTrack, expected);
        }
        OSStatus error = SGSingStreamRender(a->stream, count, a->mixed, pullOriginal, a, prefix.frames);
        for (uint32_t n = 0; n < count; n++)
            for (unsigned c = 0; c < 2; c++) ((float *)data->mBuffers[c].mData)[done+n] = a->mixed[n*2+c];
        if (error) return error;
        done += count;
    }
    if (a->epoch != atomic_load(&epoch)) {
        for (unsigned c = 0; c < 2; c++) memset(data->mBuffers[c].mData, 0, frames * sizeof(float));
    } else if (a->track) {
        unsigned tail = atomic_load_explicit(&a->markerTail, memory_order_relaxed);
        unsigned head = atomic_load_explicit(&a->markerHead, memory_order_acquire);
        uint64_t presented = SGSingStreamPresented(a->stream);
        for (unsigned n = 0; tail != head && n < 4; n++) {
            if (presented < a->markers[tail % 4].frame) break;
            a->track = a->markers[tail % 4].track;
            a->origin = a->markers[tail % 4].frame;
            a->position = 0;
            atomic_store_explicit(&a->markerTail, ++tail, memory_order_release);
        }
        double position = a->position + (SGSingStreamPresented(a->stream) - a->origin) / 44100.0;
        position = fmax(a->position, position - valueOf(atomic_load(&a->latencyBits)));
        // A natural transition keeps its audio epoch. Publish track and position as one
        // snapshot so a concurrent lyrics/lock-screen read cannot mix the two songs.
        atomic_fetch_add(&clockSequence, 1);
        atomic_store(&clockBits, bitsOf(position));
        atomic_store(&clockTrack, a->track);
        atomic_store(&clockEpoch, a->epoch);
        atomic_fetch_add(&clockSequence, 1);
    }
    return noErr;
}
SGSingAudio *SGSingAudioCreate(SGAudioStamp origin, uint32_t window, uint32_t hop, float level) {
    SGSingAudio *a = calloc(1, sizeof *a);
    if (!a) return NULL;
    a->epoch = atomic_fetch_add(&epoch, 1) + 1; a->origin = origin.sourceFrame;
    a->lastBoundary = UINT64_MAX;
    a->stream = SGSingStreamCreate(origin, window, hop, level);
    if (!a->stream) { free(a); return NULL; }
    return a;
}
SGSingStream *SGSingAudioStream(SGSingAudio *a) { return a ? a->stream : NULL; }
bool SGSingAudioAttach(SGSingAudio *a) {
    AudioStreamBasicDescription format = {0};
    if (!a || a->epoch != atomic_load(&epoch) || !SGAudioPipelineSourceFormat(&format) || format.mSampleRate != 44100 || format.mChannelsPerFrame != 2 ||
        format.mFormatID != kAudioFormatLinearPCM || format.mBitsPerChannel != 32 || format.mBytesPerFrame != sizeof(float) ||
        !(format.mFormatFlags & kAudioFormatFlagIsFloat) || !(format.mFormatFlags & kAudioFormatFlagIsNonInterleaved)) return false;
    return SGAudioPipelineSourceCanReadAhead() && SGAudioPipelineSetSourceProcessor(process, a);
}
void SGSingAudioDetach(SGSingAudio *a) {
    if (a && SGAudioPipelineClearSourceProcessor(a)) {
        uint64_t expected = a->epoch;
        atomic_compare_exchange_strong(&clockEpoch, &expected, 0);
    }
}
void SGSingAudioDestroy(SGSingAudio *a) {
    if (!a) return;
    SGSingStreamDestroy(a->stream); free(a);
}

void SGSingAudioInvalidate(void) { atomic_fetch_add(&epoch, 1); }
void SGSingAudioSetClock(SGSingAudio *a, double position, uint64_t track) {
    a->position = fmax(0, position); a->track = track;
}
void SGSingAudioExpectTrack(SGSingAudio *a, uint64_t track) {
    atomic_store(&a->expectedTrack, track);
}
bool SGSingAudioContinueTrack(SGSingAudio *a, uint64_t track) {
    if (!a || !track || a->epoch != atomic_load(&epoch) || track != atomic_load(&a->prefetchedTrack)) return false;
    uint64_t frame = atomic_load(&a->prefetchedFrame);
    if (SGSingStreamCaptured(a->stream) <= frame) return false;
    unsigned head = atomic_load_explicit(&a->markerHead, memory_order_relaxed);
    unsigned tail = atomic_load_explicit(&a->markerTail, memory_order_acquire);
    if (head - tail == 4) return false;
    a->markers[head % 4].track = track;
    a->markers[head % 4].frame = frame;
    atomic_store_explicit(&a->markerHead, head + 1, memory_order_release);
    atomic_store(&a->expectedTrack, 0);
    atomic_store(&a->prefetchedTrack, 0);
    return true;
}
bool SGSingAudioAwaitingTrack(SGSingAudio *a, uint64_t track) {
    if (!a || a->epoch != atomic_load(&epoch)) return false;
    unsigned head = atomic_load_explicit(&a->markerHead, memory_order_acquire);
    unsigned tail = atomic_load_explicit(&a->markerTail, memory_order_acquire);
    // Main only reads the newest marker it owns; the render endpoint never writes its slot.
    return head != tail && a->markers[(head - 1) % 4].track == track;
}
void SGSingAudioSetLatency(SGSingAudio *a, double seconds) {
    atomic_store(&a->latencyBits, bitsOf(isfinite(seconds) ? fmax(0, seconds) : 0));
}
bool SGSingAudioClock(uint64_t track, double *position) {
    uint64_t sequence = atomic_load(&clockSequence);
    if (sequence & 1) return false;
    uint64_t ticket = atomic_load(&clockEpoch);
    if (!ticket || ticket != atomic_load(&epoch) || track != atomic_load(&clockTrack)) return false;
    double value = valueOf(atomic_load(&clockBits));
    if (sequence != atomic_load(&clockSequence) || ticket != atomic_load(&clockEpoch) || ticket != atomic_load(&epoch)) return false;
    *position = value;
    return true;
}
