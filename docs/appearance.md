# Light and dark appearance (experimental)

The redesigned look has **Mod Settings → Appearance → Color appearance**:

- **Dark** uses deep black surfaces and light text.
- **Light** uses pale native surfaces, dark controls and artwork-colored ambient player backgrounds.
- **System**, the default, follows system appearance while the app is running.

The selector applies without closing Spotify. A missing or rejected native theme provider retains the previous working appearance and reports it in Active appearance. This feature belongs to the redesigned look, not the native look.

## Implementation

Spotify 9.1.94 has separate Swift `Encore.ColorTheme.main` and Objective-C `SPTEncoreColorTheme.main` stores. The bridge verifies both stores in one transaction before changing owned surfaces, rolling back on a failed commit. It resolves the exported native accessors with their audited Swift ABI and ownership, rather than writing hard-coded addresses.

Native views can also cache explicit colors. The adapter therefore registers known page, player and sheet roots and tracks semantic color roles together with their source values. Existing attributed text is updated without replaying stale strings. Light-origin colors reverse correctly when returning to Dark. Art, avatars, share-card payloads and intentional media colors remain outside chrome adaptation.

The remaining UIImage-backed control glyphs are adapted only under known semantic control identifiers and only if their rendered source is monochrome. Native custom slider images and active colored icons remain intact. The native saved AddTo animation remains in charge of its state. The unsaved Light glyph follows the native button's geometry.

Presented context/share sheets and the native bottom navigation gradient have independent appearance owners. Sheet materials retain their original Dark state. The bottom gradient rebuilds through its native trait callback after UIKit has propagated the selected traits, rather than by copying guessed gradient colors.

The player's own ambient palette retains its artwork hue in Light. A luminance-constrained pastel palette replaces the former near-opaque white wash. The source Dark palette and existing animation layers are retained for switching back, without re-reading the cover or restarting motion. Album covers themselves are not recolored.

Known page/player status-bar owners request matching ink without changing the root’s native child delegation or unrelated full-screen media.

Work is event-driven: preference changes, system traits, relevant native assignments and registered owner callbacks. There is no repeated whole-window color scan or per-frame general recoloring pass.

## Verification and limits

The source has local regression fixtures for provider transactions, repeated live changes, source restoration, Light-created views, attributed text, native UIKit control images, slider state, AddTo events, sheet materials, share-preview preservation, native chrome traits and ambient contrast. An isolated probe also exercises actual SpotifyShared native label/icon/theme code. Neither test environment is a substitute for testing the signed-in app.

Physical testing has exposed additional missed native owners and is still in progress. Library and mini-player Light rendering have been observed on a signed-in Duo, but comprehensive same-screen System round trips, sheet behavior and fullscreen player rendering have not yet been accepted as complete. Treat this branch as experimental, not a fully device-verified appearance release.

The native boundary is audited for Spotify 9.1.94. Other Spotify versions require independent verification. Proprietary binaries, framework probes, signing information, personal preference backups and private screenshots are not distributed.
