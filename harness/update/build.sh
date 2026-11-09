#!/bin/sh
# Builds the Updates harness for the simulator: Update.m's check and UpdatePage.m's changelog, run
# for real against GitHub. SG_VERSION is what the page believes it is running; pass one as the first
# argument to try another (./build.sh 0.12.0).
set -e
SRC=$(cd "$(dirname "$0")/../../tweak/Sources" && pwd)
OUT=$(dirname "$0")/build
VERSION=${1:-0.18.0}
rm -rf "$OUT"; mkdir -p "$OUT/UpdateHarness.app"

SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun -sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -fobjc-arc -g -O0 \
    -I"$SRC" -isysroot "$SDK" -Wno-deprecated-declarations -DSG_VERSION="\"$VERSION\"" \
    "$(dirname "$0")/main.m" \
    "$SRC"/App/About/Update.m "$SRC"/App/About/UpdatePage.m "$SRC"/App/About/UpdateNotice.m \
    "$SRC"/Settings/SGPage.m "$SRC"/Settings/SGPageStyle.m \
    "$SRC"/Core/SGLog.m "$SRC"/Core/SGPrefs.m "$SRC"/Core/SGViewTree.m "$SRC"/Core/SGGlass.m \
    "$SRC"/Core/SGBackdrop.m "$SRC"/Core/SGFlagForce.m "$SRC"/Core/SGUIMode.m "$SRC"/Core/SGAppearance.m \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework CoreImage -framework Foundation \
    -o "$OUT/UpdateHarness.app/UpdateHarness"

cat > "$OUT/UpdateHarness.app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>UpdateHarness</string>
<key>CFBundleIdentifier</key><string>com.vojta.updateharness</string>
<key>CFBundleName</key><string>UpdateHarness</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>UIUserInterfaceStyle</key><string>Dark</string>
<key>UILaunchScreen</key><dict/>
<key>UIApplicationSceneManifest</key><dict>
  <key>UIApplicationSupportsMultipleScenes</key><false/>
</dict>
</dict></plist>
PLIST
echo "built $OUT/UpdateHarness.app"
