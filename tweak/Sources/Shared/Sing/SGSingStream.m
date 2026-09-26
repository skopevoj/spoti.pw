#include "SGSingStream.h"
#include "SGSingLevel.h"
#include <math.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

struct SGSingStream {
    SGAudioStamp origin;
    uint64_t captured, presented, forwarded;
    uint32_t window, hop;
    SGSingTimeline *timeline;
    SGAudioRingBuffer *input, *output;
    float source[SGSingStreamPacketFrames * 2];
    float *vocals;
    bool workerStarted; // sole worker consumer
    bool forwardingStarted; // sole render owner
    atomic_bool paused, bypass, modelReady;
    atomic_uint levelBits, state, stopReason;
    atomic_int sourceError;
    _Atomic uint64_t queued, publishedPresented, publishedCaptured, readyFrames, processedFrames;
};

SGSingStream *SGSingStreamCreate(SGAudioStamp origin, uint32_t window, uint32_t hop, float level) {
    if ((window != 88200 && window != 176400) || hop < window / 2 || hop > window * 3 / 4 || !origin.generation) return NULL;
    SGSingStream *s = calloc(1, sizeof *s);
    if (!s) return NULL;
    s->presented = origin.sourceFrame; atomic_store(&s->publishedPresented, origin.sourceFrame);
    atomic_store(&s->publishedCaptured, origin.sourceFrame);
    s->origin = origin; s->captured = origin.sourceFrame; s->window = window; s->hop = hop;
    atomic_store(&s->modelReady, true);
    // Start with a full window of ready vocals (two completed hops). The first inference
    // duration cannot predict the next worker scheduling delay. Less overlap reduces repeated
    // inference work; the reserve still covers a full future hop before vocal reduction begins.
    s->timeline = SGSingTimelineCreate(352800, window);
    s->input = SGAudioRingCreate(1024, SGSingStreamPacketFrames, 2);
    s->output = SGAudioRingCreate(8, hop, 2);
    s->vocals = calloc((size_t)hop * 2, sizeof(float));
    if (!s->timeline || !s->input || !s->output || !s->vocals) { SGSingStreamDestroy(s); return NULL; }
    SGSingStreamSetLevel(s, level);
    SGSingTimelineBegin(s->timeline, origin, level);
    atomic_store(&s->state, SGSingTimelinePreparing);
    return s;
}
void SGSingStreamDestroy(SGSingStream *s) {
    if (!s) return;
    SGSingTimelineDestroy(s->timeline);
    SGAudioRingDestroy(s->input); SGAudioRingDestroy(s->output);
    free(s->vocals); free(s);
}
void SGSingStreamPause(SGSingStream *s, bool paused) { atomic_store(&s->paused, paused); }
void SGSingStreamSetModelReady(SGSingStream *s, bool ready) { atomic_store(&s->modelReady, ready); }
static void bypass(SGSingStream *s, SGSingStopReason reason) {
    unsigned expected = SGSingStopNone;
    atomic_compare_exchange_strong(&s->stopReason, &expected, reason);
    atomic_store(&s->bypass, true);
}
void SGSingStreamBypass(SGSingStream *s) { bypass(s, SGSingStopRequested); }
void SGSingStreamSetLevel(SGSingStream *s, float level) {
    level = SGSingClampLevel(level);
    uint32_t bits; memcpy(&bits, &level, sizeof bits); atomic_store(&s->levelBits, bits);
}
SGSingTimelineState SGSingStreamState(const SGSingStream *s) { return atomic_load(&s->state); }
uint64_t SGSingStreamPresented(const SGSingStream *s) { return atomic_load(&s->publishedPresented); }
uint64_t SGSingStreamCaptured(const SGSingStream *s) { return atomic_load(&s->publishedCaptured); }
uint64_t SGSingStreamQueued(const SGSingStream *s) { return atomic_load(&s->queued); }
uint64_t SGSingStreamReadyFrames(const SGSingStream *s) { return atomic_load(&s->readyFrames); }
uint64_t SGSingStreamProcessed(const SGSingStream *s) { return atomic_load(&s->processedFrames); }
SGSingStopReason SGSingStreamStopReason(const SGSingStream *s) { return atomic_load(&s->stopReason); }
int32_t SGSingStreamSourceError(const SGSingStream *s) { return atomic_load(&s->sourceError); }
int32_t SGSingStreamWorkerState(const SGSingStream *s) {
    return atomic_load(&s->bypass) ? -1 : atomic_load(&s->paused) ? 0 : 1;
}
static void publish(SGSingStream *s) {
    atomic_store(&s->publishedPresented, s->presented);
    atomic_store(&s->publishedCaptured, s->captured);
    atomic_store(&s->queued, SGSingTimelineQueued(s->timeline));
    atomic_store(&s->readyFrames, SGSingTimelineReadyFrames(s->timeline));
    atomic_store(&s->state, SGSingTimelineGetState(s->timeline));
}
bool SGSingStreamReadInput(SGSingStream *s, SGAudioStamp *stamp, float *pcm) {
    if (atomic_load(&s->paused) || atomic_load(&s->bypass)) return false;
    return SGAudioRingRead(s->input, stamp, pcm);
}
bool SGSingStreamReadLiveInput(SGSingStream *s, SGAudioStamp *stamp, float *pcm) {
    if (s->workerStarted) return SGSingStreamReadInput(s, stamp, pcm);
    // Off-render, bounded by the input queue's capacity. Hashing/compilation may have taken
    // seconds; inferring already emitted audio only delays activation and wastes energy.
    uint64_t first = SGSingStreamPresented(s);
    for (unsigned i = 0; i < 1024; i++) {
        if (!SGSingStreamReadInput(s, stamp, pcm)) return false;
        if (stamp->sourceFrame + stamp->frames <= first) continue;
        uint32_t skip = first > stamp->sourceFrame ? (uint32_t)(first - stamp->sourceFrame) : 0;
        stamp->sourceFrame += skip; stamp->frames -= skip;
        memmove(pcm, pcm + skip * 2, (size_t)stamp->frames * 2 * sizeof(float));
        s->workerStarted = true;
        return true;
    }
    return false;
}
bool SGSingStreamWriteVocals(SGSingStream *s, SGAudioStamp stamp, const float *pcm) {
    if (atomic_load(&s->bypass) || !SGAudioStampMatches(stamp, s->origin.generation, s->origin.track, s->origin.format) ||
        stamp.frames != s->hop) return false;
    if (!SGAudioRingWrite(s->output, stamp, pcm)) return false;
    atomic_store(&s->processedFrames, stamp.sourceFrame + stamp.frames - s->origin.sourceFrame);
    return true;
}
int32_t SGSingStreamRender(SGSingStream *s, uint32_t frames, float *pcm, SGSingSourceRead source, void *context, uint32_t available) {
    if (!s || !pcm || !source || !frames || frames > SGSingStreamMaximumRenderFrames) return -1;
    memset(pcm, 0, (size_t)frames * 2 * sizeof(float));
    if (atomic_load(&s->paused)) return 0;
    uint32_t bits = atomic_load(&s->levelBits);
    float level; memcpy(&level, &bits, sizeof level);
    SGSingTimelineSetLevel(s->timeline, level);
    if (atomic_load(&s->bypass)) SGSingTimelineBypass(s->timeline);
    // At most one whole hop per render; queued output never causes an unbounded loop.
    SGAudioStamp result;
    if (SGAudioRingRead(s->output, &result, s->vocals)) SGSingTimelineVocals(s->timeline, result, s->vocals);
    uint32_t writable = SGSingTimelineWritable(s->timeline);
    SGSingTimelineState captureState = SGSingTimelineGetState(s->timeline);
    uint64_t queued = SGSingTimelineQueued(s->timeline);
    uint32_t target = s->window * 2 + s->hop;
    uint32_t minimum = queued < frames ? frames - (uint32_t)queued : 0;
    uint32_t wanted = frames;
    if (queued < target) wanted += target - queued < frames ? target - (uint32_t)queued : frames;
    uint32_t spare = available > 5292 ? available - 5292 : 0;
    if (wanted > spare) wanted = spare;
    if (wanted < minimum) wanted = minimum;
    if (wanted > writable) wanted = writable;
    if ((captureState == SGSingTimelinePreparing || captureState == SGSingTimelineActive || captureState == SGSingTimelineRecovering) && writable < frames) {
        bypass(s, SGSingStopCapacity); SGSingTimelineBypass(s->timeline);
    } else if (writable) {
        for (uint32_t done = 0; done < wanted;) {
            uint32_t count = wanted - done;
            if (count > SGSingStreamPacketFrames) count = SGSingStreamPacketFrames;
            int32_t error = source(context, count, s->source);
            if (error) {
                atomic_store(&s->sourceError, error);
                bypass(s, SGSingStopSourceError); SGSingTimelineBypass(s->timeline); publish(s);
                return error; // a failed pull may have consumed input; never retry it
            }
            SGAudioStamp stamp = s->origin;
            stamp.sourceFrame = s->captured; stamp.frames = count;
            bool retained = SGSingTimelineCapture(s->timeline, stamp, s->source);
            s->captured += count;
            if (!retained) {
                bypass(s, SGSingStopCapacity); SGSingTimelineBypass(s->timeline);
                break;
            }
            done += count;
        }
    }
    if (atomic_load(&s->modelReady) && !atomic_load(&s->bypass)) {
        if (!s->forwardingStarted) { s->forwarded = s->presented; s->forwardingStarted = true; }
        // At most eight packets (64 KB of PCM) per render, including cold-load catch-up.
        // The playback ring, not the worker queue, owns audio accumulated during model load.
        for (unsigned n = 0; n < 8; n++) {
            uint32_t count = SGSingTimelineCopyOriginal(s->timeline, s->forwarded, s->source, SGSingStreamPacketFrames);
            if (!count) break;
            SGAudioStamp stamp = s->origin; stamp.sourceFrame = s->forwarded; stamp.frames = count;
            if (!SGAudioRingWrite(s->input, stamp, s->source)) {
                bypass(s, SGSingStopCapacity); SGSingTimelineBypass(s->timeline); break;
            }
            s->forwarded += count;
        }
    }
    uint32_t copied = SGSingTimelineRead(s->timeline, pcm, frames);
    s->presented += copied;
    SGSingTimelineState state = SGSingTimelineGetState(s->timeline);
    if (state == SGSingTimelineDraining) bypass(s, SGSingStopLateVocals);
    if (state == SGSingTimelineIdle && copied < frames) {
        // Delayed original first, then the next uncaptured source sample, even within one buffer.
        int32_t error = source(context, frames - copied, pcm + copied * 2);
        if (!error) s->presented += frames - copied;
        publish(s);
        return error;
    }
    publish(s);
    return 0;
}
