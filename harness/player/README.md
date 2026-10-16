# Player harness

Spotify's full screen player mocked under its own class names and accessibility identifiers
(from `trees/clean/player/01.txt`), so the redesign's player can be laid out, animated and
looked at on the Mac without the phone.

    THEOS=$HOME/theos ./build.sh
    xcrun simctl install <udid> build/PlayerHarness.app
    SIMCTL_CHILD_HARNESS_SCENARIO=artwork xcrun simctl launch --console-pty <udid> com.vojta.playerharness
    xcrun simctl io <udid> screenshot shot.png

Launch it on an iOS 26 simulator by UDID. The iOS 27 runtime kills an app that has a scene manifest but
no scene delegate. `SRC=<another checkout>/tweak/Sources OUT=<dir> ./build.sh` builds it against other
sources, for example an older commit, to see a bug before its fix.

`build.sh` runs `logos.pl -c generator=internal` over `PlayerLyrics.x`, `PlayerArtwork.x`,
`PlayerFooter.x`, `PlayerControls.x`, `PlayerScroll.x`, `PlayerField.x`, `PlayerAnimated.x` and the Kit's `SGRBridges.x`, and
links them with the real `Core/`, `Settings/`, `Redesigned/Kit/`, `PlayerBackgroundSettings.m`, `SGRKaraokeView` and
`Shared/LockScreenArtwork`'s order and canvas reading. `stubs.m` stands in for the hooks the harness does not compile (the Kit's
accent and repaint, the rest of the player, the lyrics store, the haptics, where Animated artwork's clips come from)
and plays a mock player: `SGRHarnessSetTrack` reports a track, with the image ids Spotify's metadata
carries, to every state observer, and `SGRHarnessSetTrackWith` the same with more metadata and the tracks up next. A song of ten timed lines plays on from launch. `main.m` also answers
for i.scdn.co through an `NSURLProtocol` handed to every session, so each picture the Kit fetches can
come late, out of order, or not at all.

`HARNESS_SCENARIO` picks what the harness does:

- `lyrics` (default) opens the lyrics at 2 s, closes them at 6 and opens them again at 10.
- `look` plays one track, then a track from another album at 8 s, whose picture reaches the screens
  0.4 s later. It shows the field, the moving background and its crossfade, and the footer row. At 3 s
  it logs whether touches on the lowered footer row (issue #54) still reach it.
- `artwork` is issue #58. Tracks change while the covers on screen lag behind (3.5 s late, past the
  Kit's last look), two skips come in a row with the older picture answering last, and one track plays
  offline. Each step checks by colour that the Kit and the field show that track's picture, and the log
  ends with `artwork checks: n of 4 right -- PASS` or `FAIL`. Before the fix it read 1 of 4.
- `taps` puts real touches on the player (`touches.m`, KIF's way: a UITouch and an IOHIDEvent sent
  through UIApplication, so hit testing, gesture recognizers and UIControl tracking all run): taps on
  the progress bar, on and beside it, with the lyrics up and not, the thumb's own drag and a tap on it,
  the times and the rows around the bar, a lyric line, and the lyrics' thumbnail with the controls
  there and with the lines alone. The duration unit is Spotify's position slider under its own class
  name, wired the way the binary wires it (began on touch down, a seek on touch up). The log ends with
  `tap checks: n of 25 right -- PASS` or `FAIL`. The iOS 26 UISlider lets go of a touch only once its
  thumb has settled, and a tap is delivered to the views late through the list's delayed touches, as
  on the phone.
- `fluid` is the Fluid artwork background: another album at 7 s (the crossfade), paused from 11 to 13 s, the
  player's open or close announced at 15 s, Speed, Saturation and Blur pushed at 17 s and put back at 20 s,
  as the page's sliders do. The log's `redesign warp:` lines pair the link's runs and stops with each step
  and give its cost a frame.

- `animated` is Animated artwork over local clips, from the folder `HARNESS_CLIPS` names (`canvas.mp4` and
  `late.mp4` at 9:16, `apple.mp4` at 3:4, `bright.mp4` nearly white; make them with ffmpeg, e.g.
  `ffmpeg -f lavfi -i testsrc2=s=360x640:r=30:d=4 -c:v libx264 -pix_fmt yuv420p canvas.mp4`, and keep them out of
  the repo). A Canvas fades in over Fluid artwork, Apple Music's cover fetched ahead takes over straight from it,
  a track without a clip goes back to Fluid artwork, a Canvas still downloading shows Fluid artwork until it
  lands, then a pause, the lyrics, Spotify's own video coming and going, the player's transition and a bright
  clip. The log ends with `animated checks: n of 15 right -- PASS` or `FAIL`. With `HARNESS_STEPPED=1` each
  step waits for `xcrun simctl spawn <udid> notifyutil -p com.vojta.harness.next`, so a script can screenshot
  every state once it has settled.

`HARNESS_BACKGROUND=0|1` stores Fluid artwork or Animated artwork (unset is the default, `animated` picks
Animated artwork), `HARNESS_OLD_BACKGROUND=0|1|2` the choice before it (Still artwork, Colour flow, Fluid artwork)
and `HARNESS_OLD_MOTION=0` the Moving background switch before that, off. `HARNESS_COVER=<path>` starts on a
picture of your own; keep real covers out of the repo.

`HARNESS_VOLUME=0` leaves out the volume row that the phone has and the tree does not.
`HARNESS_FREE=1` builds the units under the class names Spotify Free's player gives them
(`ReinventFree_ReinventFreeNpvImpl`), around the same elements; the log should read as it does without it.

A screen recording is the way to see a move:

    xcrun simctl io <udid> recordVideo -f run.mp4      # ^C to stop
    ffmpeg -ss 7.4 -t 2.2 -i run.mp4 -vf "fps=5,scale=180:-1,tile=11x1" -frames:v 1 strip.png

It also lays every unit out once a second, which is what the transforms on Spotify's title row and the
narrowed marquee labels have to survive.

What it does not cover: the real element framework's autolayout, Spotify's own scrolled layout, the
player's open and close transition, and Spotify's real image loading.
