# Speed harness

Spotify's audio chain (AudioUnitDriver2: a converter fed by a render callback, a mixer and RemoteIO, wired
with MakeConnection, slices of 4096) rebuilt with real units in the simulator, with `PlayerSpeedPitch.x`
compiled in: its AudioUnitSetProperty rebinding takes over the mixer-to-output connection exactly as on
the phone (the harness is the main executable), and its SPTPlayerState hook runs on a mock state that
computes -position the way Spotify's does.

    THEOS=$HOME/theos ./build.sh
    xcrun simctl install booted build/SpeedHarness.app
    xcrun simctl launch --console-pty booted com.vojta.speedharness

The script plays a quiet sine and steps through normal, 1.5x, 1.5x at +3 semitones, 0.75x and back,
logging how fast the converter's callback (the decoder) was drained and in how many calls, and how far
the state's position is from the content played. 2026-09-18: drained 1.00x, 1.50x, 1.50x, 0.75x, 1.00x;
position within 12 ms. 2026-10-07, iOS 26.5 runtime: the same.

Midway through the 1.5x step the decoder's callback fails forty times in a row. The converter turns
that into silence and the mod never fails a render, so the log reads 0 underruns and 0 failures: a
stutter does not reach the pass-through a failed render falls back to, and the stall of #216 (Spotify's
driver underrunning) is not reproduced here.
