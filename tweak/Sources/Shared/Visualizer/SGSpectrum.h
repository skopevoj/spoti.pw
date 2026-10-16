// The visualizer's ear (Visualizer.h): the last moments of what Spotify plays, as bars. Plain C with no
// allocation after it is set up, so the tap (VisualizerTap.x) can feed it from Core Audio's render thread
// and the view read it once a frame on the main one; tested on the Mac or Linux against harness/visualizer/.
//
// The tap writes mono samples into SGSpectrumRing, a single writer and a single reader, the reader taking
// the newest SGSpectrumWindow of them whenever it likes: a frame drawn from a window the writer moved on
// from halfway through is one 120th of a second of a slightly smeared picture, never a crash.
//
// SGSpectrumAnalyzer turns the newest `size` samples of a window into `count` bars, each 0...1: 1024 of them
// (23 ms at 44.1 kHz, so a beat shows as it lands) and the whole 2048 for Bass, which needs the finer bins
// low down, and for more than 256 bars, which want them everywhere; a Hann window, a radix-2 FFT, the bins
// summed into bands spaced evenly on a log scale over what is followed, each band's level in decibels
// against the loudest the music has been lately (falling slowly, so a quiet song still moves), then the
// strength, and a fast rise and a slower fall. Up to 128 bars each takes whole bins; past that there are more
// bars than bins down low, so each reads the spectrum at its own place between two bins and a bar is
// smoothed with its neighbours, which is what makes 1024 of them a smooth circle rather than steps. Follows, as Music Haptics has it (Shared/Haptics):
//     Everything  40 Hz to 14 kHz, every band at its level; or, with a bass share, 20 Hz to 100 Hz across that
//                 share of the ring (a fifth as it ships) and 100 Hz to 14 kHz across the rest, each part log spaced
//                 (always read between bins, as the low end has few)
//     Beat        the same bands, each lifted by how fast it just rose, so the drums jump out
// How quickly the bars rise and fall is set apart (SGSpectrumSetResponse), quick both ways as it ships.
//     Bass        25 Hz to 250 Hz across the whole ring
#pragma once
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>

enum {
    SGSpectrumWindow = 2048,
    SGSpectrumRingSize = 16384,   // a power of two, several windows at 48 kHz
    SGSpectrumMaxBands = 1024,
    SGSpectrumCoarseMost = 128,   // up to this many bars each takes whole bins
};

typedef enum { SGSpectrumEverything = 0, SGSpectrumBeat, SGSpectrumBass } SGSpectrumFollows;

typedef struct {
    float samples[SGSpectrumRingSize];
    atomic_uint written;   // samples written so far, wrapping
} SGSpectrumRing;

void SGSpectrumRingWrite(SGSpectrumRing *ring, const float *mono, uint32_t count);
// The newest SGSpectrumWindow samples, oldest first; false until that many were written.
bool SGSpectrumRingRead(SGSpectrumRing *ring, float *window);

typedef struct {
    int count;
    int size;                            // how many of the window's newest samples are analysed
    double sampleRate;
    SGSpectrumFollows follows;
    float lowHz, highHz;
    float bassShare;                     // the share of the bars for 20 to 100 Hz, 0 for one log scale
    float rise, fall;                    // a share of the way per 60th of a second
    float window[SGSpectrumWindow];   // the Hann window
    float real[SGSpectrumWindow], imaginary[SGSpectrumWindow];
    int first[SGSpectrumMaxBands + 1];   // each band's first bin, and the end of the last
    int fine;                            // more bars than SGSpectrumCoarseMost: read between bins, smoothed
    float edge[SGSpectrumMaxBands + 1];  // fine: each band's edges as a place between bins
    float level[SGSpectrumMaxBands];     // the band's last level, 0...1, before the strength
    float slow[SGSpectrumMaxBands];      // its slow average, which Beat measures a rise against
    float shown[SGSpectrumMaxBands];     // what the bars show, smoothed
    float peakDb;                        // the loudest band lately
} SGSpectrumAnalyzer;

// Before the first window, and whenever the bar count, the rate or what is followed changes. The plain reset
// spreads the bars on one log scale; the shaped one gives `bassShare` (0...0.5) of them to 20 to 100 Hz, but
// for Bass, which is all bass already.
void SGSpectrumReset(SGSpectrumAnalyzer *analyzer, int count, double sampleRate, SGSpectrumFollows follows);
void SGSpectrumResetShaped(SGSpectrumAnalyzer *analyzer, int count, double sampleRate, SGSpectrumFollows follows, float bassShare);
// How fast the bars rise and fall, each a share (0.02...1) of the way per 60th of a second; kept by a reset.
void SGSpectrumSetResponse(SGSpectrumAnalyzer *analyzer, float rise, float fall);
extern const float SGSpectrumDefaultRise, SGSpectrumDefaultFall;
// One frame: `window` from SGSpectrumRingRead (or silence), `elapsed` the seconds since the last frame,
// `strength` 0.2...2 (1 as it ships). Writes `count` bars into `bars`.
void SGSpectrumProcess(SGSpectrumAnalyzer *analyzer, const float *window, float elapsed, float strength, float *bars);
// The frame's bars fall to nothing when the music stops, at the speed they would anyway.
void SGSpectrumDecay(SGSpectrumAnalyzer *analyzer, float elapsed, float *bars);
