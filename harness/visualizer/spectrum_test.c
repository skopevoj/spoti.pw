// The visualizer's analyzer against tones: a tone lights the bars at its pitch and not the rest, Bass
// ignores the top, Beat jumps on an onset and settles on a held note, silence brings every bar down, and
// the ring hands back the newest window in order across its wrap.
//   cc -std=c11 -I tweak/Sources -x c harness/visualizer/spectrum_test.c -x c tweak/Sources/Shared/Visualizer/SGSpectrum.m -lm
#include "Shared/Visualizer/SGSpectrum.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

static SGSpectrumRing ring, scratch;
static SGSpectrumAnalyzer analyzer;
static float window_[SGSpectrumWindow], bars[SGSpectrumMaxBands];
static double phase;

static void tone(double hz, double amplitude, double rate, int samples) {
    float chunk[512];
    for (int done = 0; done < samples;) {
        int count = samples - done < 512 ? samples - done : 512;
        for (int i = 0; i < count; i++) {
            chunk[i] = (float)(amplitude * sin(phase));
            phase += 2 * M_PI * hz / rate;
        }
        SGSpectrumRingWrite(&ring, chunk, (uint32_t)count);
        done += count;
    }
}

// Sixty frames of one tone, as the view would draw them.
static void frames(double hz, double amplitude, double rate, int count, float strength) {
    for (int f = 0; f < count; f++) {
        tone(hz, amplitude, rate, (int)(rate / 60));
        assert(SGSpectrumRingRead(&ring, window_));
        SGSpectrumProcess(&analyzer, window_, 1 / 60.0f, strength, bars);
    }
}

static int loudestBar(void) {
    int best = 0;
    for (int b = 1; b < analyzer.count; b++) if (bars[b] > bars[best]) best = b;
    return best;
}

static float sum(int from, int to) {
    float total = 0;
    for (int b = from; b < to; b++) total += bars[b];
    return total;
}

static int barFor(double hz) {
    double binHz = analyzer.sampleRate / analyzer.size;
    for (int b = 0; b < analyzer.count; b++) if (hz < analyzer.first[b + 1] * binHz) return b;
    return analyzer.count - 1;
}

int main(void) {
    // The ring: nothing until a window is in, then the newest samples in order across the wrap.
    float ramp[3000];
    assert(!SGSpectrumRingRead(&scratch, window_));
    for (int round = 0; round < 12; round++) {
        for (int i = 0; i < 3000; i++) ramp[i] = (float)(round * 3000 + i);
        SGSpectrumRingWrite(&scratch, ramp, 3000);
    }
    assert(SGSpectrumRingRead(&scratch, window_));
    for (int i = 0; i < SGSpectrumWindow; i++) assert(window_[i] == (float)(36000 - SGSpectrumWindow + i));

    tone(0, 0, 44100, SGSpectrumWindow);   // the tap has run a moment before the first frame
    double rates[] = {44100, 48000};
    for (int r = 0; r < 2; r++) {
        double rate = rates[r];
        SGSpectrumReset(&analyzer, 64, rate, SGSpectrumEverything);
        frames(100, 0.8, rate, 60, 1);
        int low = loudestBar();
        assert(abs(low - barFor(100)) <= 1);
        assert(bars[low] > 0.6f);
        assert(sum(40, 64) < 0.5f);

        frames(5000, 0.8, rate, 60, 1);
        int high = loudestBar();
        assert(abs(high - barFor(5000)) <= 1);
        assert(sum(0, 20) < 0.5f);

        // Bass: the top is nothing to it, and a low tone fills the ring's middle.
        SGSpectrumReset(&analyzer, 48, rate, SGSpectrumBass);
        frames(5000, 0.8, rate, 60, 1);
        assert(sum(0, 48) < 0.5f);
        frames(90, 0.8, rate, 60, 1);
        assert(bars[barFor(90)] > 0.6f);

        // Beat: a note's onset stands higher than the same note held.
        SGSpectrumReset(&analyzer, 64, rate, SGSpectrumBeat);
        frames(0, 0, rate, 30, 1);
        frames(200, 0.5, rate, 4, 1);
        float onset = bars[barFor(200)];
        frames(200, 0.5, rate, 120, 1);
        float held = bars[barFor(200)];
        assert(onset > held + 0.2f);

        // Strength: a quiet tone shows more at 200 % than at 100 %, and never past 1.
        SGSpectrumReset(&analyzer, 64, rate, SGSpectrumEverything);
        frames(1000, 0.8, rate, 30, 1);
        frames(1000, 0.05, rate, 20, 1);
        float normal = bars[barFor(1000)];
        SGSpectrumReset(&analyzer, 64, rate, SGSpectrumEverything);
        frames(1000, 0.8, rate, 30, 2);
        frames(1000, 0.05, rate, 20, 2);
        float strong = bars[barFor(1000)];
        assert(strong > normal && strong <= 1);

        // Silence, and the decay with no window at all, bring every bar down.
        frames(0, 0, rate, 90, 1);
        assert(sum(0, 64) < 0.05f);
        frames(300, 0.8, rate, 30, 1);
        for (int f = 0; f < 120; f++) SGSpectrumDecay(&analyzer, 1 / 60.0f, bars);
        assert(sum(0, 64) < 0.01f);
    }
    // A thousand and twenty four bars: a smooth curve, a tone's peak where it belongs, nothing off the ends.
    int counts[] = {200, 512, 1024};
    for (int c = 0; c < 3; c++) {
        int n = counts[c];
        for (int r = 0; r < 2; r++) {
            double rate = rates[r];
            SGSpectrumReset(&analyzer, n, rate, SGSpectrumEverything);
            assert(analyzer.count == n && analyzer.fine);
            frames(1000, 0.8, rate, 60, 1);
            double expected = n * log(1000 / 40.0) / log(analyzer.highHz / 40.0);
            int peak = loudestBar();
            assert(fabs(peak - expected) <= n / 100.0 + 2);
            assert(bars[peak] > 0.6f);
            // The curve: no bar jumps from its neighbour by much, and the far bars are quiet.
            float steepest = 0;
            for (int b = 1; b < n; b++) steepest = fmaxf(steepest, fabsf(bars[b] - bars[b - 1]));
            assert(steepest < 0.2f * 1024 / n + 0.06f);
            assert(sum(0, n / 4) < 0.1f * n / 4 + 1);
            assert(sum(n * 3 / 4, n) < 0.1f * n / 4 + 1);
            // Bass across the whole ring, and Beat, still work and stay in 0...1.
            SGSpectrumReset(&analyzer, n, rate, SGSpectrumBass);
            frames(90, 0.8, rate, 60, 1);
            for (int b = 0; b < n; b++) assert(isfinite(bars[b]) && bars[b] >= 0 && bars[b] <= 1);
            assert(sum(0, n) > 0.5f * n * 0.2f);
            SGSpectrumReset(&analyzer, n, rate, SGSpectrumBeat);
            frames(0, 0, rate, 30, 1);
            frames(200, 0.5, rate, 4, 1);
            for (int b = 0; b < n; b++) assert(isfinite(bars[b]) && bars[b] >= 0 && bars[b] <= 1);
            frames(0, 0, rate, 120, 1);
            assert(sum(0, n) < 0.05f * n);
        }
    }
    // A fifth of the ring for 20 to 100 Hz: a 50 Hz tone peaks inside it, 1 kHz where the rest's log scale puts
    // it, and Bass ignores the share.
    int shaped[] = {64, 128, 1024};
    for (int c = 0; c < 3; c++) {
        int n = shaped[c];
        for (int r = 0; r < 2; r++) {
            double rate = rates[r];
            SGSpectrumResetShaped(&analyzer, n, rate, SGSpectrumEverything, 0.2f);
            assert(analyzer.fine && analyzer.lowHz == 20 && analyzer.bassShare == 0.2f);
            frames(50, 0.8, rate, 60, 1);
            int low = loudestBar();
            double lowWanted = n * 0.2 * log(50 / 20.0) / log(5.0);
            assert(low < n / 5 && fabs(low - lowWanted) <= n / 20.0 + 2);
            assert(sum(n / 2, n) < 0.1f * n / 2 + 1);
            frames(1000, 0.8, rate, 60, 1);
            int mid = loudestBar();
            double midWanted = n * (0.2 + 0.8 * log(10.0) / log(analyzer.highHz / 100.0));
            assert(fabs(mid - midWanted) <= n / 50.0 + 2);
            for (int b = 0; b < n; b++) assert(isfinite(bars[b]) && bars[b] >= 0 && bars[b] <= 1);
        }
    }
    SGSpectrumResetShaped(&analyzer, 64, 44100, SGSpectrumBass, 0.2f);
    assert(analyzer.bassShare == 0 && analyzer.lowHz == 25);

    // Response: a slow fall leaves more of a stopped tone up than the quick one does, and a reset keeps it.
    SGSpectrumReset(&analyzer, 64, 44100, SGSpectrumEverything);
    SGSpectrumSetResponse(&analyzer, 0.8f, 0.5f);
    frames(1000, 0.8, 44100, 60, 1);
    frames(0, 0, 44100, 6, 1);
    float quick = bars[barFor(1000)];
    SGSpectrumSetResponse(&analyzer, 0.8f, 0.1f);
    SGSpectrumReset(&analyzer, 64, 44100, SGSpectrumEverything);
    assert(analyzer.fall == 0.1f);
    frames(1000, 0.8, 44100, 60, 1);
    frames(0, 0, 44100, 6, 1);
    float slow = bars[barFor(1000)];
    assert(slow > quick + 0.2f);
    SGSpectrumSetResponse(&analyzer, SGSpectrumDefaultRise, SGSpectrumDefaultFall);

    SGSpectrumReset(&analyzer, 5000, 44100, SGSpectrumEverything);
    assert(analyzer.count == SGSpectrumMaxBands);

    // Bad input never makes a bar that is not a number.
    SGSpectrumReset(&analyzer, 3, NAN, SGSpectrumEverything);
    assert(analyzer.count == 8 && analyzer.sampleRate == 44100);
    float noise[SGSpectrumWindow];
    for (int i = 0; i < SGSpectrumWindow; i++) noise[i] = i % 2 ? INFINITY : NAN;
    SGSpectrumRingWrite(&ring, noise, SGSpectrumWindow);
    assert(SGSpectrumRingRead(&ring, window_));
    SGSpectrumProcess(&analyzer, window_, NAN, NAN, bars);
    for (int b = 0; b < analyzer.count; b++) assert(isfinite(bars[b]) && bars[b] >= 0 && bars[b] <= 1);
    SGSpectrumProcess(&analyzer, NULL, 1 / 60.0f, 1, bars);
    puts("visualizer: ring, tones, bass, beat, strength, silence, 1024 bars, the bass fifth, response and bad input passed at 44.1 and 48 kHz");
    return 0;
}
