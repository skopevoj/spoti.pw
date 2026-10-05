# Menu harness

Spotify's context menu sheet (`ContextMenu_InternalImpl.ContextMenuViewController`) mocked under its
class name and presented from a now playing controller, so `SpeedPitchMenu.x`'s hook adds Speed and
pitch the way it would on the phone. Speed and pitch themselves are stubs that log.

    THEOS=$HOME/theos ./build.sh
    xcrun simctl install <udid> build/MenuHarness.app
    xcrun simctl launch --console-pty <udid> com.vojta.menuharness [footer] [nospeed] [loading] [stuck] [open] [follow]

It has a scene delegate, so it runs on the iOS 27 simulator as well as 26. The mod's own lines
(`SGLog`) go to the unified log: `xcrun simctl spawn <udid> log stream --predicate 'eventMessage CONTAINS "[spotifyglass]"'`.

The plain run opens the menu at 1 s, the block at 3 s, moves both sliders at 5 s and closes the block
at 7 s. `footer` gives the mock table a header of Spotify's, so the block goes to the footer;
`nospeed` has the player refuse speed.

- `loading` builds the sheet the way Spotify's is laid out (a header, a content container holding a
  table sized to its content by KVO on `contentSize`, a spinner) and gives it its rows 4 s after it is
  up, the way Spotify does once its item factories have answered. It reports the sheet while loading
  and once the rows are in: they show under the block.
- `stuck` never gives it rows; the mod logs `no rows of Spotify's N s after the menu appeared`.
- `open` opens the block on a first menu, closes that menu and brings up a second one with the block
  already open, as it stays for the session.
- `follow` opens the block, sets 1.25x and +2 st, turns pitch following speed on (the pitch slider folds
  away and the pitch goes back to normal), closes and reopens the block, and turns it off again. It
  reports what the block shows each time and draws the screen into the app's tmp
  (`xcrun simctl get_app_container <udid> com.vojta.menuharness data`).

For the first second the block is on screen, every frame is checked for anything it draws in the
system tint (`tint check: 0 of the block's first N frames ...`).
