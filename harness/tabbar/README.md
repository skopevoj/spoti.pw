# Tab bar harness

The bottom of Spotify's main screen mocked under its own class names, so `Redesigned/Navbar/TabBar.x`
and `Redesigned/NowPlayingBar/NowPlayingBar.x` run for real over it on the Mac without the phone: the
tab bar container with Spotify's bar and its row of tabs, a page with a list on the tab's stack, the
now playing bar's page with its card, and Spotify's message bar (`LimitedExperienceIndicatorBar`, what
Offline and Private Session show) under the tab bar. It plays issue #33.

    THEOS=$HOME/theos ./build.sh
    xcrun simctl install <udid> build/TabBarHarness.app
    xcrun simctl launch <udid> com.vojta.tabbarharness shown
    xcrun simctl io <udid> screenshot shot.png

`build.sh` runs `logos.pl -c generator=internal` over `TabBar.x` and `NowPlayingBar.x` from the
checkout it sits in and links them with the real `Core/` and `SGRTokens.m`; `SRC=<other tweak/Sources>
./build.sh` builds an older tree instead, to compare. `stubs.m` stands in for the accent and repaint
hooks, the tab bar's composition and Mod Settings. iOS 27 ends an app with no scene delegate at
launch, so the harness has one.

The layout is the one 9.1.78 makes in a compact width, with the addresses it was read from:

- `TabBarContainerImpl`'s view has a guide from 49 pt above its safe area's bottom to its bottom
  (`viewDidLoad`, 0x1008409a8); the stack holding the tab bar is as tall as the guide and stands on
  the view's bottom, and the tab bar is as tall as the stack (0x106fabb7c).
- The page on the tab's stack gets 49 pt of safe area on top of the container's (0x10707bde4). The now
  playing bar's share of the pages' inset comes another way in Spotify; here it is a stand-in of 64 pt
  on the page, so the list's end marks where Spotify thinks the bars begin.
- The chrome puts the tab bar container above the message bar, and the now playing bar's page (64 pt,
  its content 8 pt above its bottom, 0x105345190) on the container's guide's top, which is the bottom
  anchor `MainUIContainer` gives the chrome (0x100ae0178).
- The message bar is its message plus the safe area it pads the message by, 22 pt here.

`inline` turns on the mini player in the tab bar (`SGRKeyInlinePlayer`): `MiniPlayer.m` is compiled
too, `stubs.m` stands in a player of three tracks for the state bridge and `SGKaraokePlayer` (a swipe
on the mini player skips through them), and a tap on the mock now playing bar logs `[harness] Spotify's
bar was tapped`. Scroll the list down and the bar minimizes, the mini player moving in between the first
tab and the last; scroll back to the top and it comes back. A tap on a mock tab lights it the way
Spotify does (`[harness] Spotify's Search tab was tapped`), and `library-last` leaves Create out, so
Your Library is the trailing circle: `xcrun simctl launch <udid> com.vojta.tabbarharness inline library-last`.

Launch words: `none` no message bar; `shown` one sliding in at 1.5 s; `away` one there from the start,
sliding away at 1.5 s; `cycle` in at 1.5 s and out at 4.5 s, for a recording. At 2.5 s everything is
logged in window points, with the gap between the bottom of the now playing card and the top of the
glass bar's platter (8 pt is the redesign's own, on a Face ID phone with nothing under the bar), and
half way through a slide what the screen shows of the message bar, the tab bar and the now playing bar:

    xcrun simctl spawn <udid> log show --last 1m --style compact --predicate 'eventMessage CONTAINS "[harness]" OR eventMessage CONTAINS "tab bar:"'

Before the fix the gap was -26 pt with nothing under the bar on an iPhone SE, and with the message bar
up on any phone: UIKit's glass bar is 83 pt, Spotify's bar was its 49 pt row with no inset under it,
and the glass bar stood the difference above it, over the now playing bar.

What it does not cover: Spotify's own chrome, which is Swift with no symbols (the constraints above
are read from its code, not run), the real now playing bar's content and its page's inset, the tab
bar hidden by a page, the player's open and close over the bars, and a regular width.
