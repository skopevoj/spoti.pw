# Vibrations settings harness

Mod Settings > Player's Vibrations cards (`tweak/Sources/Shared/Haptics/HapticsSettings.m`) on an SGModPage laid
out like the Player page in the redesign: the real Settings/ framework (its slider row and its rows shown while a
switch is on), the real control taps (`SGFeedback.m`, which the simulator plays silently), and `stubs.m` for Music
Haptics' engine, which logs each call with the strength and the Follows choice the hook would read.

    THEOS=$HOME/theos ./build.sh
    xcrun simctl install <udid> build/HapticsPageHarness.app
    xcrun simctl launch <udid> com.vojta.hapticspageharness controls-off music follows=1 bottom dump
    xcrun simctl io <udid> screenshot shot.png

Other agents use the simulator too: make a device of your own (`xcrun simctl create`) and address it by UDID.
Every launch clears the `spotifyglass.redesign.haptics` keys first unless `keep` is on the line; `main.m` lists the
setup words (`controls-off`, `music`, `follows=<n>`, `slow`) and the actions, played one every 0.7 s from 1 s in:
flipping a switch, dragging a slider and letting go, VoiceOver's swipe on one, the ⓘ, a tap on a row (the Follows
row, then a name in its list), and `dump`, which logs the stored keys, what the hooks read and the rows shown:

    xcrun simctl launch --console-pty <udid> com.vojta.hapticspageharness controls-off bottom toggle=2.0 slide=2.1:40 \
        toggle=3.0 slide=3.1:150 swipe=3.1:-3 dump select=3.2 select=0.1 dump

2026-09-19, iPhone 17 Pro (402pt) and iPhone 13 mini (375pt) on iOS 26.5: both switches off, Controls on with its
Strength, Music Haptics on in each Follows choice, the Follows list with a line under each choice, and the rows
fading in under a switch (`slow`); Controls at 40%, Music Haptics at 150% then 120% by VoiceOver and Beat stored
under their keys and read back by the hooks. The Audio effects page and an SGModPage without shown-while rows
(`harness/audio-effects-page`, `push=reference`) draw the same pixels as before the slider and visibility were added.

What it does not cover: a real finger on the slider, and how any strength feels, which only a phone can tell.
