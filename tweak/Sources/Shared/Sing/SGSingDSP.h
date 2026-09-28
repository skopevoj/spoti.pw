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
void SGSingMixerSetLevel(SGSingMixer *mixer, float level); // a 30 ms ramp to the new level
// Stereo interleaved. Original and vocals must have identical generation, format and source index.
// Instrumental = original - vocals; a unity instrumental gain preserves the original balance.
void SGSingMixerProcess(SGSingMixer *mixer, const float *original, const float *vocals, float *output, uint32_t frames);
// A 120 ms ramp to the aligned original, no clock change: SGSingReserveFrames at 44.1 kHz.
void SGSingMixerBypass(SGSingMixer *mixer);
