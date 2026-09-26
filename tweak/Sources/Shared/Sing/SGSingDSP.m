#include "SGSingDSP.h"
#include <math.h>

static float gain(float level) { float value = SGSingClampLevel(level); return value * value; }
static void ramp(SGSingMixer *m, float to, double seconds) {
    m->targetGain = to;
    m->remaining = (uint32_t)fmax(1, m->sampleRate * seconds);
    m->step = (to - m->gain) / m->remaining;
}
void SGSingMixerInit(SGSingMixer *m, double rate, float level) {
    *m = (SGSingMixer){.gain = gain(level), .targetGain = gain(level),
                      .sampleRate = isfinite(rate) && rate >= 8000 && rate <= 192000 ? rate : 44100};
}
void SGSingMixerSetLevel(SGSingMixer *m, float level) {
    float target = gain(level);
    if (target != m->targetGain) ramp(m, target, 0.030);
}
void SGSingMixerBypass(SGSingMixer *m) { ramp(m, 1, 0.120); }
void SGSingMixerProcess(SGSingMixer *m, const float *original, const float *vocals, float *out, uint32_t frames) {
    for (uint32_t i = 0; i < frames; i++) {
        if (m->remaining) {
            m->gain += m->step;
            if (!--m->remaining) m->gain = m->targetGain;
        }
        for (unsigned c = 0; c < 2; c++) {
            size_t at = (size_t)i * 2 + c;
            float source = isfinite(original[at]) ? original[at] : 0;
            float vocal = isfinite(vocals[at]) ? vocals[at] : 0;
            float value = source - (1 - m->gain) * vocal;
            out[at] = fmaxf(-1, fminf(1, value)); // bounded peak limiter, no per-stem normalization
        }
    }
}
double SGSingAudiblePosition(double source, uint64_t queued, double rate) {
    if (!isfinite(source)) return 0;
    if (!isfinite(rate) || rate <= 0) return fmax(0, source);
    return fmax(0, source - (double)queued / rate);
}
void SGSingInvalidate(SGSingGeneration *s, uint64_t track, uint32_t format) {
    s->generation++;
    s->track = track;
    s->format = format;
}
bool SGSingAccepts(const SGSingGeneration *s, uint64_t generation, uint64_t track, uint32_t format) {
    return s->enabled && s->generation == generation && s->track == track && s->format == format;
}
