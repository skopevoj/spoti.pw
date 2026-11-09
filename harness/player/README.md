# Player harness

Spotify's full screen player mocked under its own class names and accessibility identifiers
(from `trees/clean/player/01.txt`), so the redesign's player can be laid out, animated and
looked at on the Mac without the phone.

    THEOS=$HOME/theos ./build.sh
    xcrun simctl install <udid> build/PlayerHarness.app
    SIMCTL_CHILD_HARNESS_SCENARIO=artwork xcrun simctl launch --console-pty <udid> com.vojta.playerharness
    xcrun simctl io <udid> screenshot shot.png

Launch it on an iOS 26 or newer simulator by UDID. The harness uses a scene delegate, as required
by the iOS 27 runtime. `SRC=<another checkout>/tweak/Sources OUT=<dir> ./build.sh` builds it against other
sources, for example an older commit, to see a bug before its fix.

`build.sh` runs `logos.pl -c generator=internal` over `PlayerLyrics.x`, `PlayerArtwork.x`,
`PlayerFooter.x`, `PlayerScroll.x`, `PlayerField.x` and the Kit's `SGRBridges.x`, and links them with
the real `Core/`, `Redesigned/Kit/` and `SGRKaraokeView`. `stubs.m` stands in for the hooks the harness
does not compile (the Kit's accent and repaint, the rest of the player, the lyrics store, the haptics)
and plays a mock player: `SGRHarnessSetTrack` reports a track, with the image ids Spotify's metadata
carries, to every state observer. A song of ten timed lines plays on from launch. `main.m` also answers
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

- `resize` opens lyrics, moves the controls up until the lyrics no longer fit, then restores the
  available space. It checks that the title transforms and mask, cover visibility and chips are
  restored, the overlay is removed, and lyrics can be opened again. It also shrinks the player during
  the opening spring, then interrupts repeated open/close transitions and checks the final open and
  closed states. Periodic relayout is disabled for this scenario, so animation completion must fix
  the geometry without relying on a later pass. This catches stale overlays both after and during
  a shrinking player's transition.

`HARNESS_VOLUME=0` leaves out the volume row that the phone has and the tree does not.
`HARNESS_SIZE=466x678` selects a synthetic player viewport; without it the current scene bounds are
used. This changes the mocked player, not the simulator's display or Spotify's layout engine.

Run the resize regression at compact and wide sizes on a booted simulator:

    THEOS=$HOME/theos ./harness/player/build.sh
    ./harness/player/run-resize.sh <udid>

The matrix covers 320×667, 402×874, 466×678, 669×951 and 951×669 points. The Duo's installed
simulator device profile reports 1398×2034 and 2007×2853 pixels at 3×; the latter is also tested
rotated. These are geometry tests, not proof of Spotify's actual fold/rotation behavior. The runner
also runs the existing artwork and scroll assertions, returns nonzero on failure or missing results,
and keeps its logs in `build/resize-logs/`.


A screen recording is the way to see a move:

    xcrun simctl io <udid> recordVideo -f run.mp4      # ^C to stop
    ffmpeg -ss 7.4 -t 2.2 -i run.mp4 -vf "fps=5,scale=180:-1,tile=11x1" -frames:v 1 strip.png

It also lays every unit out once a second, which is what the transforms on Spotify's title row and the
narrowed marquee labels have to survive.

What it does not cover: the real element framework's autolayout, Spotify's own scrolled layout, the
player's open and close transition, and Spotify's real image loading.

## Duo player menu regression

`PlayerHeader.x` is included in this harness. Run `HARNESS_SCENARIO=menu` (via
`SIMCTL_CHILD_HARNESS_SCENARIO` with simctl), or:

    THEOS=$HOME/theos harness/player/build.sh
    harness/player/run-menu.sh DUO_SIMULATOR_UDID PHONE_SIMULATOR_UDID

On the Duo, this checks the real system vertical-bar region and the actual relocated
control, with five window hit-test points. The exact control retains its original
target/action, recognizer and accessibility activation. A nil-target action also
reaches the original header controller through the preserved responder chain. A noninteractive placeholder
reserves the header's space and keeps its constraints; dismissal and loss of usable
rail geometry restore the original parent, constraints and layout flags. Repeated
layouts and reopening are checked. An overlapping clear interactive sibling first
intercepts the button, then placement above it restores actual-control hit testing.
The holder never moves into UIWindow or above a presented controller.

Run both plain-subview and UIStackView arranged-subview fixtures:

    harness/player/run-menu.sh DUO_SIMULATOR_UDID PHONE_SIMULATOR_UDID
    SIMCTL_CHILD_HARNESS_MENU_STACK=1 harness/player/run-menu.sh DUO_SIMULATOR_UDID PHONE_SIMULATOR_UDID

On a phone with no native bar region, the original remains in the header. Verified
November 8, 2026 on a 466×678 Duo (region `{392,174,52,470}`) and a 402×874 iOS 26.5
phone, with both fixture types. This verifies folded native geometry, not synthetic
evidence of an open/rotated Duo; those states need separate device checks.

The real Spotify menu was exercised on a physical iPhone Duo with Spotify 9.1.94,
folded and expanded. That is separate from the mocked harness and is not a compatibility
claim for other versions. The upstream patch adds defensive restoration for detached
constraint endpoints and hidden/presented players. Both plain and stack-parent menu
fixtures passed again against the final upstream source on Duo and ordinary-phone
simulators. Full presentation and cancelled-transition coverage remains required.
