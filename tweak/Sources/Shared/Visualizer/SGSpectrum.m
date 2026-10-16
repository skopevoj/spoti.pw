// SGSpectrum.h says what this does and why it is plain C.
#include "SGSpectrum.h"
#include <math.h>
#include <string.h>

static const float kPi = 3.14159265358979f;
// The quietest a band shows anything at, under the loudest lately, and how fast that loudest falls.
static const float kRangeDb = 52, kPeakFallDbPerSecond = 6, kPeakFloorDb = -70;
// How fast the bars rise and fall: a share of the way per 60th of a second. Quick both ways, so a bar is
// where the sound is within a frame or two and drops away before the next hit.
static const float kRise = 0.8f, kFall = 0.3f;
const float SGSpectrumDefaultRise = 0.8f, SGSpectrumDefaultFall = 0.3f;   // kRise and kFall
// With a bass share: the bottom of what is shown, and where its share ends.
static const float kBassLowHz = 20, kBassSplitHz = 100;
static const int kShortWindow = 1024;
// Beat: how slowly a band's average follows it, and how much a rise over that average lifts the bar.
static const float kSlowShare = 0.08f, kBeatLift = 2.6f, kBeatBase = 0.35f;

void SGSpectrumRingWrite(SGSpectrumRing *ring, const float *mono, uint32_t count) {
    unsigned at = atomic_load_explicit(&ring->written, memory_order_relaxed);
    for (uint32_t i = 0; i < count; i++) {
        float sample = mono[i];
        ring->samples[(at + i) & (SGSpectrumRingSize - 1)] = isfinite(sample) ? sample : 0;
    }
    atomic_store_explicit(&ring->written, at + count, memory_order_release);
}

bool SGSpectrumRingRead(SGSpectrumRing *ring, float *window) {
    unsigned written = atomic_load_explicit(&ring->written, memory_order_acquire);
    static const unsigned kWindow = SGSpectrumWindow;
    if (written < kWindow) return false;
    unsigned start = written - kWindow;
    for (unsigned i = 0; i < kWindow; i++) window[i] = ring->samples[(start + i) & (SGSpectrumRingSize - 1)];
    return true;
}

void SGSpectrumReset(SGSpectrumAnalyzer *a, int count, double sampleRate, SGSpectrumFollows follows) {
    SGSpectrumResetShaped(a, count, sampleRate, follows, 0);
}

static float clampShare(float share, float low, float high) {
    return !(share >= low) ? low : share > high ? high : share;
}

void SGSpectrumSetResponse(SGSpectrumAnalyzer *a, float rise, float fall) {
    a->rise = clampShare(rise, 0.02f, 1);
    a->fall = clampShare(fall, 0.02f, 1);
}

// Where band edge `b` of `count` sits, in Hz: one log scale from low to high, or with a bass share, 20 to 100 Hz
// over that share and 100 Hz to the top over the rest.
static float edgeHz(const SGSpectrumAnalyzer *a, int b) {
    float f = (float)b / a->count;
    if (a->bassShare <= 0) return a->lowHz * powf(a->highHz / a->lowHz, f);
    if (f <= a->bassShare) return kBassLowHz * powf(kBassSplitHz / kBassLowHz, f / a->bassShare);
    return kBassSplitHz * powf(a->highHz / kBassSplitHz, (f - a->bassShare) / (1 - a->bassShare));
}

void SGSpectrumResetShaped(SGSpectrumAnalyzer *a, int count, double sampleRate, SGSpectrumFollows follows, float bassShare) {
    float rise = a->rise > 0 ? a->rise : kRise, fall = a->fall > 0 ? a->fall : kFall;
    memset(a, 0, sizeof *a);
    a->rise = rise;
    a->fall = fall;
    a->count = count < 8 ? 8 : count > SGSpectrumMaxBands ? SGSpectrumMaxBands : count;
    a->sampleRate = isfinite(sampleRate) && sampleRate >= 8000 ? sampleRate : 44100;
    a->follows = follows;
    // Bass is all bass already; elsewhere a share of the ring goes to 20 to 100 Hz, which only the longer
    // window has bins enough for, read between them.
    a->bassShare = follows == SGSpectrumBass || !(bassShare > 0) ? 0 : bassShare > 0.5f ? 0.5f : bassShare;
    a->fine = a->count > SGSpectrumCoarseMost || a->bassShare > 0;
    a->size = follows == SGSpectrumBass || a->count > 256 || a->bassShare > 0 ? SGSpectrumWindow : kShortWindow;
    a->lowHz = follows == SGSpectrumBass ? 25 : a->bassShare > 0 ? kBassLowHz : 40;
    a->highHz = follows == SGSpectrumBass ? 250 : 14000;
    if (a->highHz > a->sampleRate * 0.45) a->highHz = (float)(a->sampleRate * 0.45);
    a->peakDb = kPeakFloorDb + kRangeDb;
    for (int i = 0; i < a->size; i++) a->window[i] = 0.5f - 0.5f * cosf(2 * kPi * i / a->size);
    float binHz = (float)(a->sampleRate / a->size);
    if (a->fine) {
        // Log spaced edges as places between bins; a band narrower than a bin reads between two.
        float top = (float)(a->size / 2);
        for (int b = 0; b <= a->count; b++) {
            float place = edgeHz(a, b) / binHz;
            a->edge[b] = place < 1 ? 1 : place > top ? top : place;
            a->first[b] = (int)floorf(a->edge[b]);
        }
        return;
    }
    // Log spaced edges, each band at least one bin and after the last one's.
    int previous = 0;
    for (int b = 0; b <= a->count; b++) {
        float hz = a->lowHz * powf(a->highHz / a->lowHz, (float)b / a->count);
        int bin = (int)floorf(hz / binHz);
        if (bin < 1) bin = 1;
        if (b > 0 && bin <= previous) bin = previous + 1;
        if (bin > a->size / 2) bin = a->size / 2;
        a->first[b] = bin;
        previous = bin;
    }
}

// In place, radix 2, decimation in time.
static void fft(float *re, float *im, int n) {
    for (int i = 1, j = 0; i < n; i++) {
        int bit = n >> 1;
        for (; j & bit; bit >>= 1) j ^= bit;
        j ^= bit;
        if (i < j) {
            float t = re[i]; re[i] = re[j]; re[j] = t;
            t = im[i]; im[i] = im[j]; im[j] = t;
        }
    }
    for (int length = 2; length <= n; length <<= 1) {
        float angle = -2 * kPi / length;
        float stepRe = cosf(angle), stepIm = sinf(angle);
        for (int i = 0; i < n; i += length) {
            float wRe = 1, wIm = 0;
            for (int k = 0; k < length / 2; k++) {
                int u = i + k, v = i + k + length / 2;
                float tRe = re[v] * wRe - im[v] * wIm, tIm = re[v] * wIm + im[v] * wRe;
                re[v] = re[u] - tRe; im[v] = im[u] - tIm;
                re[u] += tRe; im[u] += tIm;
                float next = wRe * stepRe - wIm * stepIm;
                wIm = wRe * stepIm + wIm * stepRe;
                wRe = next;
            }
        }
    }
}

static float ease(float from, float to, float share, float frames) {
    float kept = powf(1 - share, frames);
    return to + (from - to) * kept;
}

void SGSpectrumProcess(SGSpectrumAnalyzer *a, const float *window, float elapsed, float strength, float *bars) {
    if (!(elapsed > 0) || elapsed > 0.25f) elapsed = 1 / 60.0f;
    float frames = elapsed * 60;
    if (!(strength > 0)) strength = 1;
    int size = a->size > 0 && a->size <= SGSpectrumWindow ? a->size : SGSpectrumWindow, offset = SGSpectrumWindow - size;
    for (int i = 0; i < size; i++) {
        a->real[i] = (window ? window[offset + i] : 0) * a->window[i];
        a->imaginary[i] = 0;
    }
    fft(a->real, a->imaginary, size);
    float loudest = -200;
    float db[SGSpectrumMaxBands];
    int last = size / 2;
    for (int b = 0; b < a->count; b++) {
        double energy = 0;
        if (a->fine && a->edge[b + 1] - a->edge[b] < 1.5f) {
            // Narrower than a bin or two: the power at the band's middle, between the two bins either side of it.
            float place = 0.5f * (a->edge[b] + a->edge[b + 1]);
            int k = (int)floorf(place), next = k + 1 > last ? last : k + 1;
            float share = place - (float)k;
            double here = a->real[k] * a->real[k] + a->imaginary[k] * a->imaginary[k];
            double after = a->real[next] * a->real[next] + a->imaginary[next] * a->imaginary[next];
            energy = here + (after - here) * share;
        } else {
            int from = a->first[b], to = a->first[b + 1] > from ? a->first[b + 1] : from + 1;
            for (int k = from; k < to && k <= last; k++) energy += a->real[k] * a->real[k] + a->imaginary[k] * a->imaginary[k];
            energy /= (to - from);
        }
        // Scaled so a full scale sine reads near 0 dB.
        float level = 10 * log10f((float)(energy * 4 / ((double)size * size)) + 1e-12f);
        db[b] = level;
        if (level > loudest) loudest = level;
    }
    a->peakDb -= kPeakFallDbPerSecond * elapsed;
    if (loudest > a->peakDb) a->peakDb = loudest;
    if (a->peakDb < kPeakFloorDb + kRangeDb) a->peakDb = kPeakFloorDb + kRangeDb;
    float levels[SGSpectrumMaxBands];
    for (int b = 0; b < a->count; b++) {
        float level = (db[b] - (a->peakDb - kRangeDb)) / kRangeDb;
        level = level < 0 ? 0 : level > 1 ? 1 : level;
        levels[b] = level * level;   // quiet bands stay low, loud ones stand out
    }
    if (a->fine) {
        // Each bar with its neighbours', the ends kept, so a ring of a thousand is a curve and not steps.
        float before = levels[0];
        for (int b = 0; b < a->count; b++) {
            float here = levels[b], after = levels[b + 1 < a->count ? b + 1 : b];
            levels[b] = 0.25f * before + 0.5f * here + 0.25f * after;
            before = here;
        }
    }
    for (int b = 0; b < a->count; b++) {
        float level = levels[b];
        float value = level;
        if (a->follows == SGSpectrumBeat) {
            float rise = level - a->slow[b];
            value = level * kBeatBase + (rise > 0 ? rise * kBeatLift : 0);
            a->slow[b] = ease(a->slow[b], level, kSlowShare, frames);
        }
        a->level[b] = level;
        value *= strength;
        if (value > 1) value = 1;
        a->shown[b] = ease(a->shown[b], value, value > a->shown[b] ? a->rise : a->fall, frames);
        bars[b] = a->shown[b];
    }
}

void SGSpectrumDecay(SGSpectrumAnalyzer *a, float elapsed, float *bars) {
    if (!(elapsed > 0) || elapsed > 0.25f) elapsed = 1 / 60.0f;
    for (int b = 0; b < a->count; b++) {
        a->shown[b] = ease(a->shown[b], 0, a->fall, elapsed * 60);
        a->slow[b] = ease(a->slow[b], 0, kSlowShare, elapsed * 60);
        bars[b] = a->shown[b];
    }
}
