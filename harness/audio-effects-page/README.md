# Audio effects page harness

Mod Settings > Audio effects (`tweak/Sources/Shared/AudioEffects/`) in a navigation controller, the way Mod
Settings pushes it: the real page, curve and file pages, the real `Settings/` framework,
`AudioEffectsSettings.m` and the engine's curve maths (`SGDSPFilters.m`), with `stubs.m` standing in for the
rest of the engine (a made-up status that changes every three seconds, fake libraries in the app's temporary
directory, and an error for any chosen file with "broken" in its name).

    THEOS=$HOME/theos ./build.sh
    xcrun simctl install <udid> build/AudioEffectsPageHarness.app
    xcrun simctl launch <udid> com.vojta.audioeffectspageharness master allon section=4 drag=9:7.5
    xcrun simctl io <udid> screenshot shot.png

Other agents use the simulator too: make a device of your own on the iOS 26.5 runtime (`xcrun simctl create`;
the iOS 27 simulator crashes this harness) and address it by UDID. Every launch clears the `spotifyglass.dsp` keys first unless `keep` is on the line; `main.m` lists the
setup words (`master`, `allon`, `broken`, `slow`) and the actions, played one every 0.7 s from 1 s in:
scrolling to a card, flipping a card's switch, a band mid-drag and let go, a preset, a tap on a row, the
file and GraphicEQ pages, an import through the document picker's delegate, Paste, a slider moved, VoiceOver's
swipe on a slider or a band, the reset's alert confirmed, and `dump`, which logs the stored keys:

    xcrun simctl spawn <udid> log show --last 1m --predicate 'process == "AudioEffectsPageHarness"' | grep '\[harness\]'

On iPhone 17 Pro (402pt) and iPhone 13 mini (375pt), iOS 26.5: every card laid out with all effects on, the
equalizer's curve the cascade's own response through its handles, the width shown as the side's level (120% for
the stored 60), long choice names moving under the title at 375pt, an error row in the engine's wording, the
credits under the reset; the values stored under the right keys, snapped to their steps.

What it does not cover: a real finger. The drag is played through the curve's own methods, so whether its
pan wins over the table's scroll when a finger starts on a handle (and loses anywhere else) is untested
here; `hit` logs which band a finger going down at and around each handle would take. Nor the document
picker's own UI, the pull-down menu of presets open, or Spotify's fonts, which the page adopts on the phone.
