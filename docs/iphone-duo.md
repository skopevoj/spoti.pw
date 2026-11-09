# Experimental iPhone Duo support

The patch targets the redesigned UI on the current `main` baseline. It does not replace
Spotify's application or scene lifecycle, and does not enable multiple concurrent players.
No device-name or fixed display-size check chooses the navigation layout. With an iOS 27.1+
SDK, the window's native vertical-bar trait and layout region select the rail.

## Build and behavior

Use Xcode with iPhoneOS 27.1+ and Theos. `make release DUO=1 IPA=/path/to/Spotify.ipa`
explicitly retargets the main executable's linked-SDK metadata; without `DUO=1`, it is not
changed. Retargeting is not recompilation, so every input version needs its own runtime
audit. The default input version remains 9.1.78. A version override only permits the build,
not a claim of support. See the README and `scripts/retarget-duo.py` for preservation checks.

- Tabs retain their order, actions, custom links, Create and the Hide labels setting.
- The rail uses a scrollable bottom-aligned group; controls retain accessible labels.
- Only the tab row's known 49pt inset is removed in vertical mode and restored afterwards.
- Miniplayer and Library content reserve the rail's region without replacing unrelated
  margins. Library list-row attributes are copied, leaving cached attributes and grids alone.
- The player relocates the real Spotify menu control, preserving its action and responder
  chain. It restores the original constraints and placement on exit.
- Playlist title/count/actions center in the usable content column. Lyrics recover from a
  resize during an opening/closing animation and close if the new geometry cannot fit them.

## Verification

Run the portable packaging, preflight, flag-cache and device-targeting regressions:

    python3 -m unittest discover -s tests -v
    scripts/check-layers.sh
    git diff --check

The real Mach-O/signing test additionally needs Xcode and `ldid`.

Compile each UIKit harness from its directory with `THEOS=$HOME/theos ./build.sh`:

- `harness/tabbar`: launch `cycle` on Duo and an ordinary phone; repeat with
  `SIMCTL_CHILD_HARNESS_HIDE_LABELS=1`. Test both defaults and customized tab orders.
- `harness/player`: `run-resize.sh SIMULATOR_UDID`, then
  `run-menu.sh DUO_SIMULATOR_UDID PHONE_SIMULATOR_UDID`; repeat menu with
  `SIMCTL_CHILD_HARNESS_MENU_STACK=1`.
- `harness/library`: run its `wrapped encoreavatar compositional gridtransition` fixture,
  plus ordinary-phone and list/grid cases documented in its README.
- `harness/playlist`: `run-centering.sh SIMULATOR_UDID` on Duo and an ordinary phone.

The original prototype's simulator runs covered native Duo rail/message-bar/miniplayer
geometry, player menu target/responder restoration, resize interruption, Library list/grid
transitions, and 288 playlist-centering assertions. Physical Spotify 9.1.94 checks covered
edge-to-edge sizing, navigation, menu presentation folded/expanded, and playlist centering
folded/expanded. The final Library full-width correction was harness-tested, not physically
re-measured. These observations do not verify the supported 9.1.78 IPA or every screen.

For this upstream draft, packaging tests and all four harness builds were rerun on Xcode
27.2. Simulator execution was blocked by CoreSimulatorService/simdiskimaged availability.
The upstream variant preserves Create and honors labels instead of the prototype's custom
icon-only defaults; it also adds defensive constraint/visibility ownership fixes. These
changes still need runtime verification, not just a successful compile.

## Before merge

Keep the PR in draft until a maintainer can run the final code with the selected Spotify
IPA. Verify both display poses and orientations, repeated fold/unfold and Split View,
leading/trailing rails and RTL, large text, labels on/off, long custom-tab lists, menu
presentation and dismissal during resize, hidden/fading/sliding chrome, playback controls,
and Library folders/list/grid/end-of-list reachability. Regress ordinary iPhone/iPad and
native UI too. In particular, menu interception repair within Spotify's presentation tree
and chrome slide-out behavior need testing against the real hierarchy, not only mocks.

The repository's CLA is a separate author decision. This patch does not express acceptance.
