# Appearance regression fixture

This simulator-only app compiles the production appearance bridge, native Swift adapter, settings picker, AMOLED hook, tokens, glass and artwork field. An independent Objective-C wrapper mock and real pure-Swift class expose the two separate stores Spotify actually uses. This replaces the incomplete original wrapper-only mock.

    THEOS=$HOME/theos sh harness/appearance/build.sh
    sh harness/appearance/run.sh <SIMULATOR_UDID>

The runner checks Dark, Light, System in both simulator appearances, unset preference in both appearances, invalid preference, nil wrapper, rejected wrapper/native writes, and the production selector in both modes. It verifies transaction rollback, later native and wrapper drift detection, 1,000 repeated native-reference ownership transfers per valid mode, persistence, restart-sheet presentation after navigation, stable glass, contrast, artwork preservation and 50 resizes. It restores the simulator's original appearance on exit. Logs and screenshots are written to build/.

The fixture does not load Spotify and is not proof that every signed-in screen uses its main theme. That still needs the scoped device test after implementation.

Never pass or use a physical device for this harness. No device tooling is called.

The integrated branch passed all 12 appearance scenarios on the iOS 26.5 simulator, plus all six tab preference scenarios across iOS 26.5 and iOS 27.1. The final Theos package build and 24 Python tests passed. These are fixture results, not signed-in app verification.
