# Pitch harness

`SGTimePitch.m` run on the Mac both ways the tweak runs it: in place over IO buffers of 1024, 4096
and odd sizes (pitch alone), and pulling a source at rates from 0.5 to 2 (speed), as the time and pitch
unit and as the varispeed that pitch following speed uses. Checks a 440 Hz sine comes out at the pitch
asked for and the source is consumed at the rate asked for, and reports the unit's pulls, underruns,
delay, cost and how far the sine is from a clean one. A click train shows what each does to a drum's
attack. With a song path it also writes the song shifted up 3 and down 4 semitones, and at 1.25x both
with the time and pitch unit at +4 and through the varispeed, into `build/` to listen to.

2026-09-25, pitch following speed: the time and pitch unit keeps 23% of each click's energy within
2 ms of its peak at 1.25x +3.86 st and 37% at 1.5x +7.02 st, where the varispeed keeps 100% at every
rate; the varispeed's pitch is exact (550.0 Hz at 1.25x), its delay 1.1 ms against 93.

    ./build.sh && build/pitch ../../../song.mp3
