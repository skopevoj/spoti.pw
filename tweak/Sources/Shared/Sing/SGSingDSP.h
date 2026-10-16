#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "SGSingLevel.h"

// Spatial voice's delay line: past the widest interaural delay (about 0.7 ms) at 192 kHz.
enum { SGSingSpatialLine = 256 };

typedef struct {
    float gain, targetGain, step;                     // the vocals'
    float instrumental, targetInstrumental, instrumentalStep;   // the rest's, below 1 only towards vocals only
    uint32_t remaining;
    double sampleRate;
    // Spatial voice: how much of the vocals goes through the head-tracked pan (0 to 1, ramped with the
    // level so a bypass lands on the untouched original), the pan it is at, the delay line of the voice
    // and the far ear's head shadow.
    float spatial, spatialTarget, spatialStep;
    uint32_t spatialRemaining;
    float pan, shadowLeft, shadowRight;
    float line[SGSingSpatialLine];
    uint32_t write;
} SGSingMixer;
// One render-thread owner. Control requests must be delivered atomically by the caller.
void SGSingMixerInit(SGSingMixer *mixer, double sampleRate, float level);
void SGSingMixerSetLevel(SGSingMixer *mixer, float level); // a 30 ms ramp to the new level
// Stereo interleaved. Original and vocals must have identical generation, format and source index.
// Instrumental = original - vocals; a unity instrumental gain preserves the original balance.
void SGSingMixerProcess(SGSingMixer *mixer, const float *original, const float *vocals, float *output, uint32_t frames);
// A 120 ms ramp to the aligned original, no clock change: SGSingReserveFrames at 44.1 kHz.
void SGSingMixerBypass(SGSingMixer *mixer);

// Spatial voice (Mod Settings > Karaoke): with head tracking AirPods, the separated vocals are panned
// against the head's turn so the voice stays in front of the listener. Set from any thread; the render
// thread reads them once per frame. The azimuth is where the voice is, in radians from straight ahead
// (positive to the right), already taken against the head.
void SGSingSpatialSetEnabled(bool enabled);
bool SGSingSpatialEnabled(void);
void SGSingSpatialSetAzimuth(float radians);
float SGSingSpatialAzimuth(void);
