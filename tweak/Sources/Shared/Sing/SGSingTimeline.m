#include "SGSingTimeline.h"
#include "SGSingDSP.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>

struct SGSingTimeline {
    float *dry, *vocals;
    uint32_t capacity, reserve;
    uint64_t captured, processed, consumed;
    uint64_t recoveryStart, recoveredAt;
    float level;
    SGAudioStamp origin;
    SGSingTimelineState state;
    SGSingMixer mixer;
};

SGSingTimeline *SGSingTimelineCreate(uint32_t capacity, uint32_t reserve) {
    if (!capacity || capacity > 44100 * 8 || !reserve || reserve > capacity) return NULL;
    SGSingTimeline *t = calloc(1, sizeof *t);
    if (!t) return NULL;
    t->dry = calloc((size_t)capacity * 2, sizeof(float));
    t->vocals = calloc((size_t)capacity * 2, sizeof(float));
    if (!t->dry || !t->vocals) { SGSingTimelineDestroy(t); return NULL; }
    t->capacity = capacity; t->reserve = reserve;
    return t;
}
void SGSingTimelineDestroy(SGSingTimeline *t) {
    if (t) { free(t->dry); free(t->vocals); free(t); }
}
void SGSingTimelineBegin(SGSingTimeline *t, SGAudioStamp origin, float level) {
    t->origin = origin;
    t->captured = t->processed = t->consumed = origin.sourceFrame;
    t->recoveryStart = UINT64_MAX;
    t->state = SGSingTimelinePreparing;
    t->level = SGSingClampLevel(level);
    SGSingMixerInit(&t->mixer, 44100, 1);
}
void SGSingTimelineSetLevel(SGSingTimeline *t, float level) {
    t->level = SGSingClampLevel(level);
    if (t->state == SGSingTimelineActive) SGSingMixerSetLevel(&t->mixer, level);
}
void SGSingTimelineBypass(SGSingTimeline *t) {
    if (t->state == SGSingTimelineIdle || t->state == SGSingTimelineDraining) return;
    if (t->state == SGSingTimelinePreparing) SGSingMixerInit(&t->mixer, 44100, 1);
    else if (t->state == SGSingTimelineActive) SGSingMixerBypass(&t->mixer);
    t->state = t->captured == t->consumed ? SGSingTimelineIdle : SGSingTimelineDraining;
}
SGSingTimelineState SGSingTimelineGetState(const SGSingTimeline *t) { return t->state; }
uint64_t SGSingTimelineConsumed(const SGSingTimeline *t) { return t->consumed; }
uint64_t SGSingTimelineQueued(const SGSingTimeline *t) { return t->captured - t->consumed; }
uint64_t SGSingTimelineReadyFrames(const SGSingTimeline *t) { return t->processed > t->consumed ? t->processed - t->consumed : 0; }
uint32_t SGSingTimelineWritable(const SGSingTimeline *t) {
    return t->state == SGSingTimelinePreparing || t->state == SGSingTimelineActive || t->state == SGSingTimelineRecovering ?
        t->capacity - (uint32_t)SGSingTimelineQueued(t) : 0;
}
static bool matches(SGSingTimeline *t, SGAudioStamp stamp) {
    return stamp.frames && SGAudioStampMatches(stamp, t->origin.generation, t->origin.track, t->origin.format) &&
        stamp.sourceFrame <= UINT64_MAX - stamp.frames;
}
static void copy(float *ring, uint32_t capacity, SGAudioStamp stamp, const float *pcm) {
    uint32_t at = stamp.sourceFrame % capacity;
    uint32_t first = stamp.frames < capacity - at ? stamp.frames : capacity - at;
    memcpy(ring + (size_t)at * 2, pcm, (size_t)first * 2 * sizeof(float));
    memcpy(ring, pcm + (size_t)first * 2, (size_t)(stamp.frames - first) * 2 * sizeof(float));
}
bool SGSingTimelineCapture(SGSingTimeline *t, SGAudioStamp stamp, const float *pcm) {
    if (!pcm || !matches(t, stamp) || stamp.sourceFrame != t->captured || stamp.frames > SGSingTimelineWritable(t)) return false;
    copy(t->dry, t->capacity, stamp, pcm);
    t->captured += stamp.frames;
    return true;
}
uint32_t SGSingTimelineCopyOriginal(const SGSingTimeline *t, uint64_t frame, float *pcm, uint32_t frames) {
    if (!pcm || frame < t->consumed || frame >= t->captured) return 0;
    if (frames > t->captured - frame) frames = (uint32_t)(t->captured - frame);
    uint32_t at = frame % t->capacity, first = frames < t->capacity - at ? frames : t->capacity - at;
    memcpy(pcm, t->dry + (size_t)at * 2, (size_t)first * 2 * sizeof(float));
    memcpy(pcm + first * 2, t->dry, (size_t)(frames - first) * 2 * sizeof(float));
    return frames;
}
bool SGSingTimelineVocals(SGSingTimeline *t, SGAudioStamp stamp, const float *pcm) {
    if (!pcm || !matches(t, stamp) || stamp.sourceFrame > t->captured ||
        stamp.frames > t->captured - stamp.sourceFrame ||
        (t->state != SGSingTimelinePreparing && t->state != SGSingTimelineActive && t->state != SGSingTimelineRecovering)) return false;
    if (stamp.sourceFrame != t->processed) {
        // Cold preparation may skip an initial prefix already emitted as original audio.
        // This exception cannot skip an audible/future hole or conceal a later missing hop.
        if (t->state != SGSingTimelinePreparing || t->processed != t->origin.sourceFrame ||
            stamp.sourceFrame < t->processed || stamp.sourceFrame > t->consumed) return false;
    }
    t->processed = stamp.sourceFrame + stamp.frames;
    // Never write expired samples back into the circular buffer: their slots may now contain
    // future audio. A packet straddling the audible cursor contributes only its live suffix.
    uint64_t expired = t->consumed > stamp.sourceFrame ? t->consumed - stamp.sourceFrame : 0;
    if (expired < stamp.frames) {
        stamp.sourceFrame += expired; stamp.frames -= (uint32_t)expired;
        copy(t->vocals, t->capacity, stamp, pcm + expired * 2);
    }
    return true;
}
uint32_t SGSingTimelineRead(SGSingTimeline *t, float *out, uint32_t frames) {
    if (!out || !frames || t->state == SGSingTimelineIdle) return 0;
    if (t->state == SGSingTimelinePreparing) {
        uint64_t ready = SGSingTimelineReadyFrames(t);
        // Keep enough aligned vocals to finish a 120 ms bypass even if the worker stops now.
        if (ready >= t->reserve && ready >= 5292 + (uint64_t)frames) {
            SGSingMixerSetLevel(&t->mixer, t->level);
            t->state = SGSingTimelineActive;
        }
    }
    // An isolated late window gets a fresh recovery budget after sustained playback.
    // Brief returns to Active must not give an overloaded worker unlimited dry/wet cycles.
    if (t->state == SGSingTimelineActive && t->recoveryStart != UINT64_MAX &&
        t->consumed - t->recoveredAt >= SGSingRecoveryLimitFrames) t->recoveryStart = UINT64_MAX;
    if (t->state == SGSingTimelineActive && SGSingTimelineReadyFrames(t) <= 5292 + (uint64_t)frames) {
        SGSingMixerBypass(&t->mixer);
        if (t->recoveryStart == UINT64_MAX) t->recoveryStart = t->consumed;
        t->state = SGSingTimelineRecovering;
    }
    if (t->state == SGSingTimelineRecovering) {
        uint64_t ready = SGSingTimelineReadyFrames(t);
        if (t->consumed - t->recoveryStart >= SGSingRecoveryLimitFrames) {
            SGSingTimelineBypass(t);
        } else if (ready >= t->reserve && ready > 5292 + (uint64_t)frames) {
            // Rebuild the same reserve required on first activation. Half a reserve let
            // a single late result toggle Sing on/off every time the worker fell behind.
            SGSingMixerSetLevel(&t->mixer, t->level);
            t->state = SGSingTimelineActive;
            t->recoveredAt = t->consumed;
        }
    }
    uint64_t queued = SGSingTimelineQueued(t);
    if (frames > queued) frames = (uint32_t)queued;
    for (uint32_t i = 0; i < frames; i++, t->consumed++) {
        size_t at = (t->consumed % t->capacity) * 2;
        float dry[2] = {t->dry[at], t->dry[at+1]}, result[2];
        if (t->consumed < t->processed) {
            SGSingMixerProcess(&t->mixer, dry, t->vocals + at, result, 1);
        } else {
            // Bypass completes before the last aligned vocal runs out. Never extrapolate a
            // missing stem from its last sample: that would add a DC offset to the original.
            result[0] = dry[0]; result[1] = dry[1];
            // A short last vocal packet can exhaust coverage inside a large render quantum.
            // Keep the mixer's next recovery ramp anchored to the dry gain actually emitted.
            if (t->mixer.gain != 1 || t->mixer.remaining) SGSingMixerInit(&t->mixer, 44100, 1);
        }
        out[i*2] = result[0]; out[i*2+1] = result[1];
    }
    if (t->state == SGSingTimelineDraining && t->consumed == t->captured) t->state = SGSingTimelineIdle;
    return frames;
}
