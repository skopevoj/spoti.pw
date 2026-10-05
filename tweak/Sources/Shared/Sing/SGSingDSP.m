#include "SGSingDSP.h"
#include <math.h>

static const double kLevelRampSeconds = 0.030, kBypassRampSeconds = 0.120;

static float gain(float level) { float value = SGSingClampLevel(level); return value * value; }
static void ramp(SGSingMixer *m, float to, float instrumentalTo, double seconds) {
    m->targetGain = to;
    m->instrumentalTarget = instrumentalTo;
    m->remaining = (uint32_t)fmax(1, m->sampleRate * seconds);
    m->step = (to - m->gain) / m->remaining;
    m->instrumentalStep = (instrumentalTo - m->instrumental) / m->remaining;
}
// Where the gains go for a level and a mode: vocals only is the vocals at full and no instrumental.
static void apply(SGSingMixer *m, float level, bool vocalsOnly) {
    m->vocalsOnly = vocalsOnly;
    float target = vocalsOnly ? 1 : gain(level), instrumental = vocalsOnly ? 0 : 1;
    if (target != m->targetGain || instrumental != m->instrumentalTarget) ramp(m, target, instrumental, kLevelRampSeconds);
}
void SGSingMixerInit(SGSingMixer *m, double rate, float level) {
    *m = (SGSingMixer){.gain = gain(level), .targetGain = gain(level), .instrumental = 1, .instrumentalTarget = 1,
                      .sampleRate = isfinite(rate) && rate >= 8000 && rate <= 192000 ? rate : 44100};
}
void SGSingMixerSetLevel(SGSingMixer *m, float level) { apply(m, level, m->vocalsOnly); }
void SGSingMixerSetVocalsOnly(SGSingMixer *m, float level, bool vocalsOnly) { apply(m, level, vocalsOnly); }
void SGSingMixerBypass(SGSingMixer *m) { ramp(m, 1, 1, kBypassRampSeconds); }
void SGSingMixerProcess(SGSingMixer *m, const float *original, const float *vocals, float *out, uint32_t frames) {
    for (uint32_t i = 0; i < frames; i++) {
        if (m->remaining) {
            m->gain += m->step;
            m->instrumental += m->instrumentalStep;
            if (!--m->remaining) { m->gain = m->targetGain; m->instrumental = m->instrumentalTarget; }
        }
        for (unsigned c = 0; c < 2; c++) {
            size_t at = (size_t)i * 2 + c;
            float source = isfinite(original[at]) ? original[at] : 0;
            float vocal = isfinite(vocals[at]) ? vocals[at] : 0;
            // With the instrumental whole this is the original formula exactly, so a bypass or a full level returns the
            // original sample for sample; only vocals only (or the ramp into it) takes the second form.
            float value = m->instrumental == 1 ? source - (1 - m->gain) * vocal : m->instrumental * (source - vocal) + m->gain * vocal;
            out[at] = fmaxf(-1, fminf(1, value)); // bounded peak limiter, no per-stem normalization
        }
    }
}
