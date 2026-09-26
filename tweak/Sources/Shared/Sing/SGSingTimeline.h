// Render-thread-owned, preallocated aligned PCM. The worker sends its results through an SPSC
// queue; only the render consumer calls this API. No allocation after Create, no locks or waits.
#pragma once
#include "Shared/Audio/SGAudioRingBuffer.h"

typedef enum {
    SGSingTimelineIdle,
    SGSingTimelinePreparing,
    SGSingTimelineActive,
    SGSingTimelineDraining,
    SGSingTimelineRecovering
} SGSingTimelineState;
enum { SGSingRecoveryLimitFrames = 44100 * 8 };
typedef struct SGSingTimeline SGSingTimeline;

SGSingTimeline *SGSingTimelineCreate(uint32_t capacityFrames, uint32_t reserveFrames);
void SGSingTimelineDestroy(SGSingTimeline *timeline); // both endpoints stopped
// Begin also invalidates all retained audio. The caller must change generation before a seek.
void SGSingTimelineBegin(SGSingTimeline *timeline, SGAudioStamp origin, float vocalLevel);
void SGSingTimelineSetLevel(SGSingTimeline *timeline, float level);
void SGSingTimelineBypass(SGSingTimeline *timeline);
SGSingTimelineState SGSingTimelineGetState(const SGSingTimeline *timeline);
uint32_t SGSingTimelineWritable(const SGSingTimeline *timeline);
uint64_t SGSingTimelineConsumed(const SGSingTimeline *timeline);
uint64_t SGSingTimelineQueued(const SGSingTimeline *timeline);
uint64_t SGSingTimelineReadyFrames(const SGSingTimeline *timeline);
// Stereo interleaved, 44.1 kHz. Reject mismatch, gap or overflow. During recovery, late output
// still advances the worker cursor, but only its not-yet-audible suffix is retained.
bool SGSingTimelineCapture(SGSingTimeline *timeline, SGAudioStamp stamp, const float *original);
// Render owner only: copy a still-retained original prefix to the worker input queue.
uint32_t SGSingTimelineCopyOriginal(const SGSingTimeline *timeline, uint64_t sourceFrame, float *stereo, uint32_t frames);
bool SGSingTimelineVocals(SGSingTimeline *timeline, SGAudioStamp stamp, const float *vocals);
// Preparing emits available original PCM immediately and advances its audible clock.
// Draining can return a prefix: pull the remaining frames directly only AFTER this prefix.
// Active underrun ramps to aligned dry audio and keeps capturing while the worker catches up.
// Recovery never rewinds/rebuffers and requires a full reserve before reducing vocals again.
// Its eight-second budget resets only after eight uninterrupted seconds of active playback.
uint32_t SGSingTimelineRead(SGSingTimeline *timeline, float *output, uint32_t frames);
