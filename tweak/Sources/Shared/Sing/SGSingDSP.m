#include "SGSingDSP.h"
#include <math.h>
#include <stdatomic.h>
#include <string.h>

static const double kLevelRampSeconds = 0.030, kBypassRampSeconds = 0.120;
// Spatial voice: the widest interaural delay, how far the far ear's shadow goes, and how fast the pan
// follows the head (a one-pole smoother, about 40 ms), so a jump in the motion data never clicks.
static const double kMaximumDelaySeconds = 0.00066, kPanSeconds = 0.040;
static const float kMaximumShadow = 0.65f;
static const float kPi = 3.14159265358979f, kQuarterPi = 0.785398163397448f, kRootTwo = 1.41421356237310f;

static atomic_bool sg_spatialEnabled;
static atomic_uint sg_azimuthBits;

void SGSingSpatialSetEnabled(bool enabled) { atomic_store(&sg_spatialEnabled, enabled); }
bool SGSingSpatialEnabled(void) { return atomic_load(&sg_spatialEnabled); }
void SGSingSpatialSetAzimuth(float radians) {
    if (!isfinite(radians)) radians = 0;
    uint32_t bits; memcpy(&bits, &radians, sizeof bits); atomic_store(&sg_azimuthBits, bits);
}
float SGSingSpatialAzimuth(void) {
    uint32_t bits = atomic_load(&sg_azimuthBits);
    float radians; memcpy(&radians, &bits, sizeof radians);
    return radians;
}

// Past the original mix the vocals stay whole and the instrumental fades, on the same curve.
static float gain(float level) { float value = fminf(1, SGSingClampLevel(level)); return value * value; }
static float instrumental(float level) {
    float value = SGSingClampLevel(level);
    if (value <= 1) return 1;
    float left = SGSingVocalsOnlyLevel - value;
    return left * left;
}
static void ramp(SGSingMixer *m, float to, float instrumentalTo, double seconds) {
    m->targetGain = to;
    m->targetInstrumental = instrumentalTo;
    m->remaining = (uint32_t)fmax(1, m->sampleRate * seconds);
    m->step = (to - m->gain) / m->remaining;
    m->instrumentalStep = (instrumentalTo - m->instrumental) / m->remaining;
}
static void rampSpatial(SGSingMixer *m, float to, double seconds) {
    if (to == m->spatialTarget && (m->spatialRemaining || m->spatial == to)) return;
    m->spatialTarget = to;
    m->spatialRemaining = (uint32_t)fmax(1, m->sampleRate * seconds);
    m->spatialStep = (to - m->spatial) / m->spatialRemaining;
}
void SGSingMixerInit(SGSingMixer *m, double rate, float level) {
    memset(m, 0, sizeof *m);
    m->gain = gain(level); m->targetGain = gain(level);
    m->instrumental = instrumental(level); m->targetInstrumental = instrumental(level);
    m->sampleRate = isfinite(rate) && rate >= 8000 && rate <= 192000 ? rate : 44100;
}
void SGSingMixerSetLevel(SGSingMixer *m, float level) {
    float target = gain(level), rest = instrumental(level);
    if (target != m->targetGain || rest != m->targetInstrumental) ramp(m, target, rest, kLevelRampSeconds);
    rampSpatial(m, SGSingSpatialEnabled() ? 1 : 0, kLevelRampSeconds);
}
void SGSingMixerBypass(SGSingMixer *m) {
    ramp(m, 1, 1, kBypassRampSeconds);
    rampSpatial(m, 0, kBypassRampSeconds);
}

// The voice, folded to its centre, panned to where it should be heard: constant power across the two
// ears, the far one a little later and a little duller, the way a head shadows a voice off to one side.
// Its side (the reverb and the doubling spread across the stereo field) is left where it was.
static void spatialize(SGSingMixer *m, float left, float right, float *outLeft, float *outRight) {
    float mid = 0.5f * (left + right), side = 0.5f * (left - right);
    float azimuth = SGSingSpatialAzimuth();
    float target = sinf(fmaxf(-kPi, fminf(kPi, azimuth)));
    float smoothing = (float)(1 - exp(-1 / (m->sampleRate * kPanSeconds)));
    m->pan += (target - m->pan) * smoothing;
    float pan = fmaxf(-1, fminf(1, m->pan));

    m->line[m->write] = mid;
    float delay = fabsf(pan) * (float)(kMaximumDelaySeconds * m->sampleRate);
    if (delay > SGSingSpatialLine - 2) delay = SGSingSpatialLine - 2;
    uint32_t whole = (uint32_t)delay;
    float fraction = delay - (float)whole;
    float a = m->line[(m->write + SGSingSpatialLine - whole) % SGSingSpatialLine];
    float b = m->line[(m->write + SGSingSpatialLine - whole - 1) % SGSingSpatialLine];
    float late = a + (b - a) * fraction;
    m->write = (m->write + 1) % SGSingSpatialLine;

    // sqrt(2) so the voice straight ahead is as loud in each ear as it was.
    float angle = (pan + 1) * kQuarterPi;
    float nearGain = kRootTwo * (pan >= 0 ? sinf(angle) : cosf(angle));
    float farGain = kRootTwo * (pan >= 0 ? cosf(angle) : sinf(angle));
    float shadow = fabsf(pan) * kMaximumShadow;
    float nearEar = mid * nearGain, farEar = late * farGain;
    if (pan >= 0) {
        m->shadowLeft += (1 - shadow) * (farEar - m->shadowLeft);
        *outRight = nearEar - side; *outLeft = m->shadowLeft + side;
        m->shadowRight = nearEar;
    } else {
        m->shadowRight += (1 - shadow) * (farEar - m->shadowRight);
        *outLeft = nearEar + side; *outRight = m->shadowRight - side;
        m->shadowLeft = nearEar;
    }
}

void SGSingMixerProcess(SGSingMixer *m, const float *original, const float *vocals, float *out, uint32_t frames) {
    for (uint32_t i = 0; i < frames; i++) {
        if (m->remaining) {
            m->gain += m->step;
            m->instrumental += m->instrumentalStep;
            if (!--m->remaining) { m->gain = m->targetGain; m->instrumental = m->targetInstrumental; }
        }
        if (m->spatialRemaining) {
            m->spatial += m->spatialStep;
            if (!--m->spatialRemaining) m->spatial = m->spatialTarget;
        }
        size_t at = (size_t)i * 2;
        float source[2], vocal[2];
        for (unsigned c = 0; c < 2; c++) {
            source[c] = isfinite(original[at + c]) ? original[at + c] : 0;
            vocal[c] = isfinite(vocals[at + c]) ? vocals[at + c] : 0;
        }
        if (m->spatial > 0) {
            // Original - vocals + the level's share of the vocals, those panned by Spatial voice's share.
            float placed[2];
            spatialize(m, vocal[0], vocal[1], &placed[0], &placed[1]);
            for (unsigned c = 0; c < 2; c++) {
                float voice = vocal[c] + (placed[c] - vocal[c]) * m->spatial;
                float value = (source[c] - vocal[c]) * m->instrumental + m->gain * voice;
                out[at + c] = fmaxf(-1, fminf(1, value));
            }
        } else {
            for (unsigned c = 0; c < 2; c++) {
                // The instrumental whole, the original's own arithmetic, so a bypass lands on it exactly.
                float value = m->instrumental == 1 ? source[c] - (1 - m->gain) * vocal[c]
                                                   : (source[c] - vocal[c]) * m->instrumental + m->gain * vocal[c];
                out[at + c] = fmaxf(-1, fminf(1, value)); // bounded peak limiter, no per-stem normalization
            }
        }
    }
}
