# Library harness

Spotify's Your Library page mocked under its own class names and accessibility identifiers (from
`trees/clean/library/03.txt`, recorded 2026-09-16), so `Redesigned/Library/LibraryHeader.x` can be laid out
and looked at on the Mac without the phone.

    THEOS=$HOME/theos ./build.sh
    xcrun simctl install <udid> build/LibraryHarness.app
    xcrun simctl launch <udid> com.vojta.libraryharness            # first look
    xcrun simctl launch <udid> com.vojta.libraryharness back       # then the pass the page gets coming back from a playlist
    xcrun simctl io <udid> screenshot shot.png

`build.sh` runs `logos.pl -c generator=internal` over `LibraryHeader.x` from the checkout it sits in and
links it with the real `Core/` and `Redesigned/Kit/` sources; `SRC=<other tweak/Sources> ./build.sh` builds
an older tree instead, to compare. `stubs.m` stands in for the hook files the harness does not compile.

It plays issue #21. The page comes up with the header's control row holding Search alone. At 0.8 s the
header's model lands: Recents and Create show, and the page lays out in the same turn. The mock of
`AutoLayoutStackView` (the real one's ivars are `observationsDictionary` and `needsCoalescedLayoutUpdate`)
places what changed on the next turn of the main queue, in a pass of its own container that reaches
neither the header nor the page. So at the page's pass a button just shown still stands at the row's
origin, where 03.txt has the hidden Recents. Before the fix the moves worked out on that pass stayed:
Search ends up next to the title, left of Recents, and Create goes off the screen. A page pass later (`back`)
put Search on top of Recents, which the old code never placed. After the fix the row's own pass places
everything again.

Launch words: `back` adds the page pass at 2.4 s. `steady` builds the header with the model already in it.
`nocreate` leaves Create out of the model, and `norecents` leaves Recents out (the account the tree was
recorded on). Each moment is logged with where every control landed in the header:

    xcrun simctl spawn <udid> log show --last 1m --style compact --predicate 'eventMessage CONTAINS "[harness]" OR eventMessage CONTAINS "redesign library"'

What it does not cover: the real stack's constraints and when its coalesced update actually runs, the
element framework behind the avatar, the list's rows (`LibraryRows.x`) and the folder page.

`wrapped` inserts the header container introduced in Spotify 9.1.94. Run both `wrapped steady` and
`wrapped` (delayed model) to cover discovery and the header’s own layout hook. Each report asserts
that the redesigned title exists. This is a hierarchy regression fixture, not a real Duo test.

`encoreavatar` replaces the legacy AdaptiveFaceContainer with the 48pt SideDrawerButton Encore
control seen in the Spotify 9.1.94 Duo device snapshot (2026-11-08). Run `wrapped encoreavatar
steady norecents` and `wrapped encoreavatar back` to cover immediate and coalesced control layout.
The default retains the legacy avatar fixture. These assertions test header placement, not the
real app's bottom chrome or inherited safe-area insets.

`safepage` reproduces the live controller's horizontal safe-area constraints on the page. Assertions
require the page and collection viewport to fill the host bounds in vertical navigation, and to
retain the original safe-area width otherwise. Checked on the Duo iOS 27.1 simulator (466pt full
viewport) and iPhone iOS 26.5 simulator (402pt unchanged). The collection has no added side inset; verified row-content constraints keep text clear of the
system status area and floating controls while the cell and separator span the viewport. This
still needs real-device visual verification.

`rows` compiles the real LibraryRows hook and uses the actual Playlist.Row.Library inner-stack
constraint pattern from the device snapshot (top/bottom +/-8, leading/trailing +/-16). With
`safepage wrapped encoreavatar steady norecents rows`, assertions check full-width cells and
separators, inner content clearance, zero added scroll side insets, and bottom edge hidden only
in vertical navigation. Verified on Duo (466pt cell, 350pt inner stack) and ordinary iPhone
(402pt cell, 370pt inner stack). Scroll top/bottom insets remain Spotify's responsibility.

`compositional gridtransition` reproduces the final physical probe: configuration None but an
explicit SafeArea section still returns 382pt list attributes inside a 466pt viewport. The fixture
retains upstream per-item and elements attributes and asserts that the production hooks return
466pt copies without changing upstream objects, x/y, heights or content size. It checks full-width
list cells/separators, unchanged safe-width grid cards, switching back to list, and reused rows after
scrolling. The ordinary phone remains unchanged. No compositional configuration mutation is used.
This is a regression fixture, not physical app verification.
