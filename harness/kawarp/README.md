# Player background settings harness

The redesign's rows on the Player page (`Redesigned/NowPlayingBar/NowPlayingBarSettings.m`): the Background choice,
Animated artwork's Sources page (`Shared/LockScreenArtwork`'s order page under a key of the player's) and the Fluid
artwork page (`Redesigned/Player/PlayerBackgroundSettings.m`), on the real `Settings/` framework, with the preview
drawn by the Kit's renderer (`Redesigned/Kit/SGRWarp.m`). The player's side is `harness/player`'s `fluid` and
`animated` scenarios.

    ./build.sh
    xcrun simctl install <udid> build/KawarpHarness.app
    SIMCTL_CHILD_HARNESS_COVER=<picture> xcrun simctl launch <udid> com.vojta.kawarpharness dump select=1.1 slide=0.2:3 dump

Launch it on an iOS 26 simulator by UDID; the iOS 27 runtime kills an app that has a scene manifest but no
scene delegate. `main.m` lists the setup words (`old=<n>` stores an older build's Background, `old-off` its Moving background
switch off, to see either read as Fluid artwork) and the actions, one every 1.2 s from 1 s in. `dump` says what the
player reads, both artwork orders included. Without `HARNESS_COVER` nothing is
playing and the preview warps its generated sample; keep real covers out of the repo.
