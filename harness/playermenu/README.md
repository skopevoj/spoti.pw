# Player menu harness

The redesign's player menu (`Redesigned/Player/PlayerMenu.x`, drawn by `SGRPlayerMenu.m`) run for real over
a mock of Spotify's context menu sheet: a player with its ⋯ (`id=Context menu`), and the sheet presented from
it the way 9.1.78 nests it, whose rows are controls carrying the item's number as their accessibility
identifier. Share (9) pushes a page onto the sheet, Lyrics (28) turns itself on in place, every other row
dismisses the sheet. Speed and pitch are stubs that log.

    THEOS=$HOME/theos ./build.sh
    xcrun simctl install <udid> build/PlayerMenuHarness.app
    xcrun simctl launch --console-pty <udid> com.vojta.playermenuharness [hold|more|speed|follow|tile|share|lyrics|outside|pending] [loading|slow|stuck] [differ] [trace] [dump] [dimmings]

Every run taps the ⋯ at 1 s and reports the card, its rows top to bottom and whether Spotify's sheet is out
of sight at 2.2 s; the scenario then taps something on the card at 3 s and reports again. From the tap on,
every frame for a second is checked for Spotify's sheet, its dimming or a system UIDimmingView showing
(`flash check`). `loading` hands the sheet its rows 1.5 s after it is up and `slow` 7 s after; `stuck` never
does, and the card stays either way. `pending` taps Add to playlist on the last run's rows before Spotify's are
in: with `loading` it is fired once they are, with `stuck` Spotify's sheet is shown 4 s after the tap. `dump` logs the presentation's container, `dimmings` where the system's UIDimmingViews are and whether
they are hidden.

`differ` gives the sheet another track's rows than the ones the last run kept (no Remove from this playlist,
Lyrics on), so with `loading` or `slow` the card has to move from the kept rows to these. `trace` logs, every
frame from the tap, the card's scale, its rows' alpha and the first row's frame whenever they change: that is
how the open and a change of rows are checked for animation, since the simulator's screen recordings keep no
reliable timing.
