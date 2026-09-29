# Lyrics harness

The redesign's lyrics view (`Redesigned/Lyrics/SGRKaraokeView.m`) playing a song on a clock of the
harness's own, so lines sung over each other, instrumental breaks, pronunciations and translations can
be looked at on the Mac without the phone. The songs are TTML read by the real `SGTTML.m`, or LRC timed
by the real estimate in `KaraokeTiming.m`.

    ./build.sh                  # this checkout; ./build.sh old builds HEAD's for a before and after, OPT=-O2 optimised
    xcrun simctl install <udid> build/new/LyricsHarness.app
    xcrun simctl launch <udid> com.vojta.lyricsharness.new -song duet -at 114000 -pauseAt 117600
    xcrun simctl io <udid> screenshot shot.png

`stubs.m` stands in for the player and the store: the position runs from `-at` at `-rate` and holds at
`-pauseAt` (for `-holdFor` seconds, then runs on). `main.m` lists every launch argument; the lyrics'
own settings are taken by their keys, e.g. `-spotifyglass.redesign.lyricsPronunciation 1`.

The fixtures are real TTML and LRC with every word swapped for filler of the same script and length
(`fixtures/anonymise.py`), so each keeps its song's timing and structure without its lyrics:

- `duet` two voices and a group over each other, three at once in places (from about 99 s)
- `romanised` Japanese with Apple's word timed pronunciation, backing rows, an 11 s break at 114.7 s
- `translated` Spanish with Apple's English translation and backing rows carried into it
- `both` Korean with both, and English lines the pronunciation leaves out
- `plain` line timed LRC, the words estimated, with a 13 s intro and a break after the first line
- `linetimed` TTML timed by the line only (BiniLyrics' line timed shape): two voices, two lines sung
  over each other at 42.4 s, a Hebrew line at 50.6 s, a 9 s break at 85.4 s, translations
- `spotify-line`, `spotify-static` Spotify's own color-lyrics JSON, LINE_SYNCED and UNSYNCED, read by
  the real `SGKaraokeLinesFromBody`; `static` plain text, as LRCLIB's plainLyrics
  (these four are written by `fixtures/linetimed.py` from `plain`'s timing)
- `rtl` (built in) right to left lines among left to right ones, a second voice, a break before the
  last line; `rtlx` the same with translations and a romanization

Lines timed by the line light up whole; `-spotifyglass.lyricsSimulateWords 1` sweeps them on the
estimate instead, as the Lyrics page's switch does. Untimed lyrics show every line lit, whatever `-at`.

Run it on an iOS 26 simulator, by UDID: iOS 27 refuses an app without a scene delegate and crashes it
at launch. `-dumpTo PATH` writes the dump to a file, for when `--console` shows nothing.

A real file goes in with `-file /path/song.ttml`: the simulator reads the Mac's paths.

`-perf LABEL` logs the view's per frame cost (its display link's `tick`) every 240 frames; run with
`simctl launch --console` to read it. `-dump 1` prints the lines as read, with their pronunciations and
translations, and quits. `-openMenu 3` opens the pronunciation and translation menu three seconds in,
`-toggleAt 3` switches both over as the menu would, and `-light 1` puts the window in light mode.

A screen recording catches the motion: `simctl io <udid> recordVideo -f run.mp4`, then e.g.
`ffmpeg -i run.mp4 -vf "fps=10,crop=1206:520:0:560,scale=233:-1,tile=12x1" -frames:v 1 strip.png`.

What it does not cover: Spotify's pages around the view (the player's stage is only its size, `-player 1`),
the lyrics arriving late or changing track, and the device's frame pacing.
