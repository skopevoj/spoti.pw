#!/bin/sh
# Builds the player background settings harness for the simulator: the redesign's Player page rows, the
# Fluid artwork page with its preview and Animated artwork's Sources page, on the real Settings/ framework
# and the Kit's renderer.
set -e
SRC=$(cd "$(dirname "$0")/../../tweak/Sources" && pwd)
OUT=$(dirname "$0")/build
rm -rf "$OUT"; mkdir -p "$OUT/KawarpHarness.app"

SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun -sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -fobjc-arc -g -O0 \
    -I"$SRC" -isysroot "$SDK" -Wall -Werror -Wno-deprecated-declarations \
    "$(dirname "$0")/main.m" "$(dirname "$0")/stubs.m" \
    "$SRC"/Redesigned/Player/PlayerBackgroundSettings.m "$SRC"/Redesigned/NowPlayingBar/NowPlayingBarSettings.m \
    "$SRC"/Redesigned/Kit/SGRWarp.m "$SRC"/Redesigned/Kit/SGRTokens.m \
    "$SRC"/Settings/SGPage.m "$SRC"/Settings/SGPageStyle.m "$SRC"/Settings/SGModPage.m "$SRC"/Settings/SGGlowSwitch.m "$SRC"/Settings/SGOrderPage.m \
    "$SRC"/Shared/LockScreenArtwork/LockScreenArtwork.m "$SRC"/Shared/LockScreenArtwork/LockScreenArtworkSettings.m \
    "$SRC"/Core/SGLog.m "$SRC"/Core/SGPrefs.m "$SRC"/Core/SGViewTree.m "$SRC"/Core/SGFlagForce.m "$SRC"/Core/SGUIMode.m \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework Foundation -framework Metal -framework MediaPlayer \
    -o "$OUT/KawarpHarness.app/KawarpHarness"

cat > "$OUT/KawarpHarness.app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>KawarpHarness</string>
<key>CFBundleIdentifier</key><string>com.vojta.kawarpharness</string>
<key>CFBundleName</key><string>KawarpHarness</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>UIUserInterfaceStyle</key><string>Dark</string>
<key>UILaunchScreen</key><dict/>
<key>UIApplicationSceneManifest</key><dict>
  <key>UIApplicationSupportsMultipleScenes</key><false/>
</dict>
</dict></plist>
PLIST
echo "built $OUT/KawarpHarness.app"
