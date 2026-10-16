#!/bin/sh
# Builds the speed harness for the simulator: Spotify's audio chain rebuilt with real Core Audio units and
# PlayerSpeedPitch.x's rebinding and render callback run on it for real.
set -e
SRC=$(cd "$(dirname "$0")/../../tweak/Sources" && pwd)
OUT=$(dirname "$0")/build
rm -rf "$OUT"; mkdir -p "$OUT/gen" "$OUT/SpeedHarness.app"
"$THEOS/bin/logos.pl" -c generator=internal "$SRC/Shared/Player/SpeedPitch.x" > "$OUT/gen/PlayerSpeedPitch.m"
"$THEOS/bin/logos.pl" -c generator=internal "$SRC/Shared/Audio/SGAudioPipeline.x" > "$OUT/gen/SGAudioPipeline.m"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun -sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -fobjc-arc -g -O1 \
    -I"$SRC" -I"$SRC/Shared/Player" -isysroot "$SDK" -Wno-deprecated-declarations \
    "$(dirname "$0")/main.m" "$OUT"/gen/*.m "$SRC/Shared/Audio/SGAudioSourceQueue.m" "$SRC"/Shared/Player/SGTimePitch.m "$SRC"/Core/SGRebind.m \
    "$SRC"/Core/SGLog.m "$SRC"/Core/SGPrefs.m "$SRC"/Core/SGUIMode.m "$SRC"/Core/SGFlagForce.m \
    -framework UIKit -framework QuartzCore -framework AudioToolbox -framework AVFoundation -framework Foundation \
    -o "$OUT/SpeedHarness.app/SpeedHarness"
cat > "$OUT/SpeedHarness.app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SpeedHarness</string>
<key>CFBundleIdentifier</key><string>com.vojta.speedharness</string>
<key>CFBundleName</key><string>SpeedHarness</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>UILaunchScreen</key><dict/>
<key>UIApplicationSceneManifest</key><dict><key>UIApplicationSupportsMultipleScenes</key><false/></dict>
</dict></plist>
PLIST
echo "built $OUT/SpeedHarness.app"
