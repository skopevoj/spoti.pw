#!/bin/sh
# Builds the Vibrations settings harness for the simulator: Shared/Haptics' settings and control taps, the
# Settings/ framework as they are in the tweak, stubs.m for Music Haptics.
set -e
SRC=$(cd "$(dirname "$0")/../../tweak/Sources" && pwd)
OUT=$(dirname "$0")/build
rm -rf "$OUT"; mkdir -p "$OUT/HapticsPageHarness.app"

SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun -sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -fobjc-arc -g -O0 \
    -I"$SRC" -isysroot "$SDK" -Wall -Werror -Wno-deprecated-declarations \
    "$(dirname "$0")/main.m" "$(dirname "$0")/stubs.m" "$(dirname "$0")/../haptics/system-stub.m" \
    "$SRC"/Shared/Haptics/HapticsSettings.m "$SRC"/Shared/Haptics/SGFeedback.m \
    "$SRC"/Settings/SGPage.m "$SRC"/Settings/SGPageStyle.m "$SRC"/Settings/SGModPage.m "$SRC"/Settings/SGGlowSwitch.m \
    "$SRC"/Core/SGLog.m "$SRC"/Core/SGPrefs.m "$SRC"/Core/SGViewTree.m "$SRC"/Core/SGFlagForce.m "$SRC"/Core/SGUIMode.m \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework Foundation \
    -o "$OUT/HapticsPageHarness.app/HapticsPageHarness"

cat > "$OUT/HapticsPageHarness.app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>HapticsPageHarness</string>
<key>CFBundleIdentifier</key><string>com.vojta.hapticspageharness</string>
<key>CFBundleName</key><string>HapticsPageHarness</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>UIUserInterfaceStyle</key><string>Dark</string>
<key>UILaunchScreen</key><dict/>
<key>UIApplicationSceneManifest</key><dict>
<key>UIApplicationSupportsMultipleScenes</key><false/>
<key>UISceneConfigurations</key><dict>
  <key>UIWindowSceneSessionRoleApplication</key><array><dict>
    <key>UISceneConfigurationName</key><string>Default</string>
    <key>UISceneDelegateClassName</key><string>AppDelegate</string>
  </dict></array>
</dict>
</dict>
</dict></plist>
PLIST
echo "built $OUT/HapticsPageHarness.app"
