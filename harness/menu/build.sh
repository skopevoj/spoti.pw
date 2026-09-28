#!/bin/sh
# Builds the menu harness for the simulator: SpeedPitchMenu.x's hook run for real on a mock of
# Spotify's context menu sheet.
set -e
SRC=$(cd "$(dirname "$0")/../../tweak/Sources" && pwd)
OUT=$(dirname "$0")/build
rm -rf "$OUT"; mkdir -p "$OUT/gen" "$OUT/MenuHarness.app"
"$THEOS/bin/logos.pl" -c generator=internal "$SRC/Shared/Player/SpeedPitchMenu.x" > "$OUT/gen/SpeedPitchMenu.m"

SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun -sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -fobjc-arc -g -O0 \
    -I"$SRC" -I"$SRC/Shared/Player" -isysroot "$SDK" -Wno-deprecated-declarations \
    "$(dirname "$0")/main.m" "$OUT"/gen/*.m \
    "$SRC"/Core/SGLog.m "$SRC"/Core/SGPrefs.m "$SRC"/Core/SGViewTree.m "$SRC"/Core/SGGlass.m \
    "$SRC"/Core/SGBackdrop.m "$SRC"/Core/SGFlagForce.m "$SRC"/Core/SGUIMode.m "$SRC"/Settings/SGPageStyle.m \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework CoreImage -framework Foundation \
    -o "$OUT/MenuHarness.app/MenuHarness"

cat > "$OUT/MenuHarness.app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MenuHarness</string>
<key>CFBundleIdentifier</key><string>com.vojta.menuharness</string>
<key>CFBundleName</key><string>MenuHarness</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>UIUserInterfaceStyle</key><string>Dark</string>
<key>UILaunchScreen</key><dict/>
<key>UIApplicationSceneManifest</key><dict>
  <key>UIApplicationSupportsMultipleScenes</key><false/>
  <key>UISceneConfigurations</key><dict>
    <key>UIWindowSceneSessionRoleApplication</key><array><dict>
      <key>UISceneConfigurationName</key><string>Default</string>
      <key>UISceneDelegateClassName</key><string>SGHarnessScene</string>
    </dict></array>
  </dict>
</dict>
</dict></plist>
PLIST
echo "built $OUT/MenuHarness.app"
