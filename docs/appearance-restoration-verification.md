# Appearance restoration verification

This revision replaces the earlier launch-only appearance implementation with an event-driven live theme bridge. It preserves the branch's independent rail visibility, label preferences, miniplayer constraint ownership and player-menu constraint restoration fixes.

## Corrections covered

- Both native theme providers are committed and read back before the selected appearance changes. Failed commits retain the previous working state.
- Explicit native text and control colors retain semantic source roles, including colors first assigned in Light mode. Attributed strings preserve current content.
- The native navigation gradient refreshes after its UIKit traits propagate; native geometry and layer identity remain intact.
- Context/share sheets have scoped material ownership, restore native Dark state and relinquish ownership when reused elsewhere. Share-preview payloads are excluded.
- AddTo glyph placement waits for meaningful native bounds. Known UIImage-backed monochrome controls are adapted without replacing artwork, colored control state or native saved animations.
- Light player ambience retains artwork hue with a contrast-constrained pastel palette. Existing animation layers and the Dark source palette remain available for reversal.
- Status-bar styling is limited to known page/player owners with registered content. Root child delegation and unrelated fullscreen media remain unchanged.

## Test scope

The combined simulator fixture exercises the production provider bridge and native surface/glyph/sheet/status adapters over controlled native-view mocks. The six geometry harnesses use an explicit semantic-surface stub and test layout separately. The integrated source passed its full Theos package build, architecture-layer and diff checks, all 24 Python packaging/preflight tests, and all 12 combined appearance cases: 30,294 assertions with zero failures. All six standalone geometry harnesses compiled, and all six tab preference/selection scenarios passed across the ordinary-phone and Duo simulators. Light and Dark fixture previews were visually inspected.

A separate isolated probe exercised actual SpotifyShared 9.1.94 label/icon/theme code, including live transitions, Light-origin colors and rollback. It excluded sheet and UIImage/Lottie paths; those paths have fixture coverage instead. Proprietary inputs and probe artifacts are not distributed.

## Physical acceptance remains pending

A prior candidate was observed on a signed-in Duo but still had mixed sheets and a stale lower fade after switching back to Dark. Those findings motivated this restoration revision. Previous screenshots do not demonstrate that the current code passes.

The current appearance work remains experimental until the same signed-in screens pass repeated System Light/Dark changes, fullscreen-player controls, context/share presentation and dismissal, and folding/rotation. Local fixtures and installation alone do not establish acceptance.

No private screenshots, original Spotify binaries, signed IPAs, preference backups, profiles or certificates are included in this repository.
