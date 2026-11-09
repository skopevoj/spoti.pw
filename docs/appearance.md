# Launch-applied light and dark appearance

The redesigned look has **Mod Settings → Appearance → Color appearance**:

- **Dark** selects deep black backgrounds and light text.
- **Light** selects Spotify's semantic light theme and matching redesign surfaces, labels, glass and settings.
- **System (at launch)**, the default when unset, selects the phone's current appearance when Spotify starts. A later system change takes effect on the next launch.

Changing this choice offers to close Spotify; reopen it to apply. “Active appearance” distinguishes the current theme from a pending selection, and reports an unavailable or drifted provider rather than silently calling it Light. This is deliberate: the native theme setter does not announce a repaint, and changing only some of its cached colors in place would leave mixed appearances. No whole-window color scan, repeated recoloring timer, or generic foreground/background guessing was added.

## Native boundary

The original implementation updated only `SPTEncoreColorTheme.main`, which is an Objective-C wrapper with its own independent store. That was insufficient: Spotify's actual Swift `Encore.ColorTheme.main` has a different store. The initial mock fixture reproduced only the wrapper and missed this boundary.

The corrected bridge resolves the exported native Swift main/light/dark accessors, uses their verified `swiftcall` ABI and opaque-reference ownership, and applies the native and Objective-C providers in one launch transaction. Getters return an owned native Swift reference, the native setter consumes it, and readbacks are released through `swift_release`. If either provider rejects the transition, the previous values are restored before owned light styling is enabled. Missing APIs fail closed with visible status. There are no hard-coded runtime addresses or raw static writes.

Evidence in cached SpotifyShared 9.1.94: native main getter/setter `0x1bf4c`/`0x1bf98` target `0x445500`; wrapper getter/setter `0x1c0e4`/`0x1c140` target `0x445508`. The app imports the native main address accessor at approximately 1,700 call sites. Runtime code resolves names, not these offsets. Native getters return +1 and the setter consumes +1, as established from disassembly and exercised by the real Swift fixture.

Explicit dark-theme clients still require device coverage. The implementation does not globally replace dark with light, which would break intentional inverted and over-media content. Later direct writes are exposed by the Active appearance readback. The native look is unchanged; this feature belongs to the redesign.

## Owned surfaces

Redesign text and glass use the same resolved launch policy. Artwork images remain unchanged. A pale overlay on the artwork background supplies a controlled light surface without modifying album covers or animation palettes. Base-surface cleanup remains limited to the page roots already managed by the redesign. Known page roots and mod settings adopt matching UIKit traits; there is no global controller override.

## Verification

`harness/appearance` builds the real bridge, AMOLED hook, tokens, glass and artwork field with independent Objective-C and real native Swift providers. It exercises the actual dynamic-symbol/Swift ABI boundary and 1,000 repeated ownership transfers per valid mode. The production settings picker is also checked for persistence and its restart prompt. It checks explicit/system/invalid choices, bridge rejection and missing theme fallback, attempted native theme drift, contrast, image preservation and repeated resizes. Screenshots are fixture previews, not captures of Spotify itself. Existing artwork/footer/player/layout regressions remain useful for the surrounding changes.

The corrected two-provider implementation has not yet been verified across the screens of a signed-in Spotify app. Treat this as experimental source, not a device-verified release. The native boundary was audited against Spotify 9.1.94; the repository's older default IPA version is not an appearance compatibility claim.

## Actual provider verification

The corrected adapter was also tested against the actual cached SpotifyShared binary in an isolated simulator probe. A copy changed only its platform metadata/signature; all 46 file-backed code/data sections matched the original. The probe reproduced the original wrapper-only failure, then passed both-provider light/dark transitions, rollback and 1,000 repeated transfers. Real Light colors were white background, black text and #656565 subdued text; Dark was #121212, white and #B3B3B3. Over-media text stayed white. This verifies the actual native theme code, not coverage of every screen in the signed-in app. The proprietary binary and local probe outputs are not distributed.
