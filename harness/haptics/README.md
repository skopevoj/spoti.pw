# Music Haptics harness

Two halves: the analyzer on the Mac, and the hook in the simulator.

## The analyzer on the Mac (`main.m`, `score.py`)

`SGMusicAnalyzer.m` as the tweak compiles it, over a song decoded at the output's rate and handed over in IO
buffers, the way `MusicHaptics.x` hands it the output's buffers. Every event goes to a CSV (K a kick's tap, S a
snare's, L the rumble's level); `score.py` matches the taps one to one within 50 ms (mir_eval) against librosa's
onsets for each Follows choice, beside what random taps at the same rate score. With demucs' stems beside the
song (`<song>.drums.wav`, `.bass.wav`, `.vocals.wav`, htdemucs) it also scores against the drums, the low end
and the vocals.

    ./build.sh && build/haptics <song> <events.csv> [rate] [frames]
    python score.py <song.wav> <events.csv>        # numpy, scipy, soundfile, librosa, mir_eval

2026-09-19, `song.mp3` beside the repo (`test.mp3` is the same audio with a cover, and gives the same events), at
48 kHz in buffers of 1024: the event stream for Everything is identical to the analyzer's before Follows existed
(19,938 events at 48 kHz, 19,896 at 44.1; only the taps' kind is new), and 44.1 kHz scores within 0.01 of 48 kHz.

| Follows | taps a second | against | precision | recall (stronger half) | at random |
|---|---|---|---|---|---|
| Everything, Beat | 3.31 | the mix's percussive onsets | 0.73 | 0.68 (0.84) | 0.30 / 0.28 |
| Everything, Beat | 3.31 | the drums stem | 0.66 | 0.89 (0.94) | 0.21 / 0.28 |
| Bass | 2.03 | the low end (drums and bass under 150 Hz) | 0.84 | 0.70 (0.73) | 0.22 / 0.18 |

The rumble is over its start level 76% of the time in Everything and Bass, and never plays in Beat.

A Vocals choice was tried and left out. Without a separation model the one cheap handle on a voice is that it is
mixed in the middle: per FFT bin (2048 at 44.1 kHz, hops of 512) the centre was kept by L/R similarity, 250 Hz to
4 kHz, broadband rises (a drum lifts every bin at once) held down, onsets picked from SuperFlux-style flux,
causally. Against the onsets of demucs' vocal stem it scored, at its best, precision 0.53 and recall 0.59 on
`song.mp3` (3.4 taps a second; at random 0.26 and 0.29), 0.35 / 0.55 on a sung line (`say -v Cellos` over a
beat; at random 0.19) and 0.66 / 0.65 on a spoken one; the same picker on the vocal stem alone scores 0.72 / 0.74,
so what fails is the separation, not the picking. Of the taps that hit no syllable, 47% fell where nobody sings,
and no cheap cue told those stretches apart (the best, the share of the sound in the centre, AUC 0.6). It needs
a real separation model.

## The hook in the simulator (`sim/`)

Spotify's chain rebuilt with real units (as `harness/audio-effects/sim`), with `MusicHaptics.x` (logos, internal
generator), the analyzer and the Vibrations settings compiled into an app whose main executable is the harness,
so its `AudioOutputUnitStart` goes through the rebound import slot as Spotify's does. `sim/fakehaptics.m`
stands in for Core Haptics and counts what it is asked to play. A beat of a kick and a snare a second plays
through a 44.1 kHz client into the simulator's 48 kHz hardware while a script checks each Follows choice, the
strength at 50% and 200%, the switch off and on, then a 16-bit interleaved client.

    THEOS=$HOME/theos ./build-sim.sh
    xcrun simctl install <udid> build/sim/HapticsHarness.app
    xcrun simctl launch --console-pty <udid> com.vojta.hapticsharness
    xcrun simctl spawn <udid> log show --last 2m --predicate 'eventMessage CONTAINS "music haptics"'

`./build-sim.sh before <dir>` builds the same against an older `MusicHaptics.x`, `Haptics.h` and analyzer put in
`<dir>`, running only the format steps. Use a device of your own (`xcrun simctl create`), by UDID.

2026-09-19: every step passes. Beat sends no rumble, Bass no snare, 50% halves the taps (0.44 from 0.88) and the
rumble's loudest (0.162 from 0.322), 200% doubles the rumble (0.64). The hook now listens at the hardware's
48 kHz float, a buffer per channel, whatever the client ("from 44100 Hz ... Spotify hands it"). Before, it read
the client format off the input scope: it ran the analyzer at 44.1 kHz on 48 kHz buffers, and a 16-bit
interleaved client made it read the float buffers as integers (taps 0.57 strong instead of 0.89).
