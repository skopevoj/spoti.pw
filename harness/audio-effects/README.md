# Audio effects harness

Two halves, both building the third-party C (`vendor/audio`) for their platform first.

## The engine on the Mac (`main.m`)

The engine (`tweak/Sources/Shared/AudioEffects/SGDSP*.m`) as the tweak compiles it. A song decoded with
ExtAudioFile, and test signals, go through the engine in the slices iOS hands its output unit (1024, 4096, 470
and 471 in turn, 512, and a mix down to single frames), and each check prints a line:

- bypass exact to the sample one block late, hotter than full scale too, and again once effects are switched off;
- output gain, the limiter's ceiling with +12 dB into it, its release;
- the equalizer's bands at their gains by a stepped sine (smile, all +12, alternating ±12, one band, random),
  the page's curve between them, at 44.1 kHz too; bass boost lifting a quiet 40 Hz tone by the shelf's gain and
  holding a loud one under its knee;
- the Graphic EQ's FIR against its curve; the convolver: Dirac responses of 1, 2 and 4 paths as identity, a random
  4 path response past the head against `vDSP_conv`, a 44.1 kHz response resampled, the three modes, `.irs`,
  FLAC, 16-bit, and the files it refuses;
- ViPER DDC files written by the harness, feedback added or subtracted, at 44.1, 48 and 96 kHz; Liveprog: channel
  swap, a slider default, a delay line in script memory, @block, functions, errors with the file's line;
- reverb tails by preset, stereo widening (mono stays mono), crossfeed (mono stays mono, presets lightest to
  strongest), the tube (level kept, 2nd over 3rd harmonic, aliases, its filters' delay), the compander (flat at 0,
  dynamics narrowed at +1 and widened at -1);
- crossfades: no bend sharper than the effect's own while it is switched on, off and swapped;
- everything on: finite, under the ceiling, no allocation or free on the render thread (counted with
  `malloc_logger`, so Apple's reverb unit is counted too); rate changes, a reset, a thread changing settings while
  another processes; the cost of each effect per 1024-frame block. WAVs go to the out dir.

    ./build.sh && build/audio-effects <song> <out dir>
    ./build.sh thread && build/audio-effects-thread <song> <out dir>
    ./build.sh address && build/audio-effects-address <song> <out dir>

A last word `stress` runs the convolver, the threaded checks, rate changes and Liveprog only.

## The hook in the simulator (`sim/main.m`)

Spotify's chain rebuilt with real units (a converter fed by a render callback, a mixer, RemoteIO, wired with
MakeConnection), with `AudioEffects.x` (logos, internal generator), its settings, libraries and engine compiled
into an app whose main executable is the harness, so its `AudioOutputUnitStart` goes through the shared
audio pipeline's rebound import slot as Spotify's does. The effects register in that pipeline after speed/pitch
and before haptics. A second render notify, added after the output started and so after the effects', measures
what they left in the buffer while a script flips settings: the switch off and a gain that must not apply, the
switch on and -12 dB, a Liveprog script from the library swapping the channels, a reverb ringing out after the
source stops, a file missing from the library and its error, then a 16-bit interleaved client at 48 kHz.

    THEOS=$HOME/theos ./build-sim.sh
    xcrun simctl install <udid> build/sim/AudioEffectsHarness.app
    xcrun simctl launch --console-pty <udid> com.vojta.audioeffectsharness

Use a device of your own on the iOS 26.5 runtime (`xcrun simctl create`), by UDID, and launch it once: the iOS 27
simulator crashes harnesses like this one, and every crash puts a dialog on the Mac's screen. The tweak's own lines
are in the unified log:
`xcrun simctl spawn <udid> log show --last 2m --predicate 'eventMessage CONTAINS "[spotifyglass]"'`.
