#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "SGSingLevel.h"

typedef struct {
    float gain, targetGain, step;
    uint32_t remaining;
    double sampleRate;
    // The instrumental's own gain, ramped together with `gain`: 1 normally, 0 while only the vocals play.
    float instrumental, instrumentalTarget, instrumentalStep;
    bool vocalsOnly;
} SGSingMixer;
// One render-thread owner. Control requests must be delivered atomically by the caller.
void SGSingMixerInit(SGSingMixer *mixer, double sampleRate, float level);
void SGSingMixerSetLevel(SGSingMixer *mixer, float level); // a 30 ms ramp to the new level
// Vocals only: a 30 ms ramp that takes the instrumental out and the vocals to full, whatever the level; off, back to
// `level`. The level keeps its own say again as soon as it is off.
void SGSingMixerSetVocalsOnly(SGSingMixer *mixer, float level, bool vocalsOnly);
// Stereo interleaved. Original and vocals must have identical generation, format and source index.
// Instrumental = original - vocals; a unity instrumental gain preserves the original balance.
// output = instrumental gain * (original - vocals) + vocal gain * vocals.
void SGSingMixerProcess(SGSingMixer *mixer, const float *original, const float *vocals, float *output, uint32_t frames);
// A 120 ms ramp to the aligned original, no clock change: SGSingReserveFrames at 44.1 kHz.
void SGSingMixerBypass(SGSingMixer *mixer);
