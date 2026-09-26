#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "SGSingLevel.h"

typedef struct {
    float gain, targetGain, step;
    uint32_t remaining;
    double sampleRate;
} SGSingMixer;
// One render-thread owner. Control requests must be delivered atomically by the caller.
void SGSingMixerInit(SGSingMixer *mixer, double sampleRate, float level);
void SGSingMixerSetLevel(SGSingMixer *mixer, float level);
// Stereo interleaved. Original and vocals must have identical generation, format and source index.
// Instrumental = original - vocals; a unity instrumental gain preserves the original balance.
void SGSingMixerProcess(SGSingMixer *mixer, const float *original, const float *vocals, float *output, uint32_t frames);
void SGSingMixerBypass(SGSingMixer *mixer); // 120 ms ramp to the aligned original, no clock change
double SGSingAudiblePosition(double sourceSeconds, uint64_t queuedSourceFrames, double sampleRate);

typedef struct {
    uint64_t generation, track;
    uint32_t format;
    bool enabled, paused;
} SGSingGeneration;
// Call before seek/track/route/interruption/disable. Async results from the old generation expire.
void SGSingInvalidate(SGSingGeneration *state, uint64_t track, uint32_t format);
bool SGSingAccepts(const SGSingGeneration *state, uint64_t generation, uint64_t track, uint32_t format);
