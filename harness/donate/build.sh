#!/bin/sh
# Builds the donate harness for the simulator: the donate and certificate sheets and the page style, nothing of Spotify's.
set -e
SRC=$(cd "$(dirname "$0")/../../tweak/Sources" && pwd)
OUT=$(dirname "$0")/build
VERSION=${1:-0.18.0}
rm -rf "$OUT"; mkdir -p "$OUT/DonateHarness.app"

SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun -sdk iphonesimulator clang -target arm64-apple-ios26.0-simulator -fobjc-arc -g -O0 \
    -I"$SRC" -isysroot "$SDK" -Wno-deprecated-declarations -DSG_VERSION='"0.20.0"' \
    "$(dirname "$0")/main.m" "$SRC"/App/Donate/Donate.m "$SRC"/App/Sheet/SGCardSheet.m "$SRC"/App/About/Certificate.m \
    "$SRC"/Settings/*.m \
    "$SRC"/Core/SGLog.m "$SRC"/Core/SGPrefs.m "$SRC"/Core/SGViewTree.m "$SRC"/Core/SGGlass.m \
    "$SRC"/Core/SGBackdrop.m "$SRC"/Core/SGFlagForce.m "$SRC"/Core/SGUIMode.m \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework CoreImage -framework Foundation -framework Symbols \
    -o "$OUT/DonateHarness.app/DonateHarness"

cat > "$OUT/DonateHarness.app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>DonateHarness</string>
<key>CFBundleIdentifier</key><string>com.vojta.donateharness</string>
<key>CFBundleName</key><string>DonateHarness</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>UIUserInterfaceStyle</key><string>Dark</string>
<key>UILaunchScreen</key><dict/>
<key>UIApplicationSceneManifest</key><dict>
  <key>UIApplicationSupportsMultipleScenes</key><false/>
</dict>
</dict></plist>
PLIST
# A free Apple ID's profile, 7 days long with 2 left, so the certificate sheet and row have a date.
cat > "$OUT/DonateHarness.app/embedded.mobileprovision" <<PROFILE
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CreationDate</key><date>$(date -u -v-5d +%Y-%m-%dT%H:%M:%SZ)</date>
<key>ExpirationDate</key><date>$(date -u -v+2d +%Y-%m-%dT%H:%M:%SZ)</date>
<key>UUID</key><string>harness</string>
</dict></plist>
PROFILE
echo "built $OUT/DonateHarness.app"
