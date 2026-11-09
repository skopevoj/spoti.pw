# Appearance regression fixture

This simulator-only app compiles the production appearance bridge, native Swift adapter, settings picker, native surface/glyph/sheet/status adapters, AMOLED hook, tokens, glass and artwork field. Independent Objective-C and pure-Swift providers expose the separate stores used by the bridge. It does not load Spotify.

    THEOS=$HOME/theos sh harness/appearance/build.sh
    sh harness/appearance/run.sh <SIMULATOR_UDID>

The 12 cases cover Dark, Light, System in both simulator appearances, an unset or invalid preference, nil/rejected providers, and the production selector. Checks include provider rollback, repeated live transitions, native reference ownership, source-color restoration in both directions, Light-created views, mutable attributed text, native UIKit image/slider state, AddTo glyph geometry, native gradient refresh timing, sheet materials and reuse, share-preview preservation, scoped status ink, and ambient hue/contrast without changing cover art. The runner restores the simulator's original appearance on exit. Logs and fixture screenshots are written to build/.

The fixture cannot prove that every real signed-in Spotify screen uses these paths. Physical fullscreen player, context/share sheets and same-screen System round trips remain acceptance work. See [appearance details](../../docs/appearance.md) and [verification limits](../../docs/appearance-restoration-verification.md).

The separate album, artist, Library, player, playlist and tabbar harnesses test geometry using `harness/native-surface-stubs.m` at the native semantic surface boundary. The complete adapter is exercised here instead. Those geometry tests must not be described as full native appearance coverage.

Never pass a physical device to this harness. It calls simulator tools only.
