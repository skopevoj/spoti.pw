# Speed harness

Spotify's audio chain (AudioUnitDriver2: a converter fed by a render callback, a mixer and RemoteIO, wired
with MakeConnection, slices of 4096) rebuilt with real units in the simulator, with `PlayerSpeedPitch.x`
compiled in: its AudioUnitSetProperty rebinding takes over the mixer-to-output connection exactly as on
the phone (the harness is the main executable), and its SPTPlayerState hook runs on a mock state that
computes -position the way Spotify's does.

    THEOS=$HOME/theos ./build.sh
    xcrun simctl install booted build/SpeedHarness.app
    xcrun simctl launch --console-pty booted com.vojta.speedharness

The script plays a quiet 440 Hz sine and steps through normal, 1.5x, 1.5x at +3 semitones, 1.5x and
0.75x with pitch following speed (the varispeed), 0.75x at +3 and back, logging how fast the converter's
callback (the decoder) was drained, the pitch the output played, and how far the state's position is from
the content played. 2026-09-18: drained 1.00x, 1.50x, 1.50x, 0.75x, 1.00x; position within 12 ms.
