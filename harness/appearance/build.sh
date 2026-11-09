#!/bin/sh
set -e
SRC=${SRC:-$(cd "$(dirname "$0")/../../tweak/Sources" && pwd)}
OUT=${OUT:-$(dirname "$0")/build}
rm -rf "$OUT"; mkdir -p "$OUT/gen" "$OUT/AppearanceHarness.app"

for f in Redesigned/Kit/SGRAppearance.x Redesigned/Kit/SGRAmoled.x; do
    name=$(basename "$f" .x)
    "$THEOS/bin/logos.pl" -c generator=internal "$SRC/$f" > "$OUT/gen/$name.m"
done

SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
mkdir -p "$OUT/AppearanceHarness.app/Frameworks"
xcrun swiftc -emit-library -parse-as-library -module-name NativeThemeFixture \
    -target arm64-apple-ios17.0-simulator -sdk "$SDK" \
    -Xlinker -install_name -Xlinker @rpath/NativeThemeFixture.dylib \
    "$(dirname "$0")/NativeThemeFixture.swift" -o "$OUT/AppearanceHarness.app/Frameworks/NativeThemeFixture.dylib"
xcrun -sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -fobjc-arc -g -O0 \
    -I"$SRC" -I"$SRC/Redesigned/Kit" -I"$OUT/gen" -isysroot "$SDK" \
    -Wno-deprecated-declarations \
    "$(dirname "$0")/main.m" "$(dirname "$0")/stubs.m" \
    "$OUT"/gen/*.m \
    "$SRC"/Core/SGLog.m "$SRC"/Core/SGPrefs.m "$SRC"/Core/SGViewTree.m "$SRC"/Core/SGGlass.m \
    "$SRC"/Core/SGBackdrop.m "$SRC"/Core/SGFlagForce.m "$SRC"/Core/SGUIMode.m "$SRC"/Core/SGAppearance.m \
    "$SRC"/Redesigned/Kit/SGRTokens.m "$SRC"/Redesigned/Kit/SGRPalette.m "$SRC"/Redesigned/Kit/SGRField.m "$SRC"/Redesigned/Kit/SGRFlow.m \
    "$SRC"/Redesigned/Kit/SGRGlass.m "$SRC"/Redesigned/Kit/SGRGlyph.m "$SRC"/Redesigned/Kit/SGRRestyle.m \
    "$SRC"/Redesigned/Kit/SGRActionRow.m "$SRC"/Redesigned/Kit/SGRDownload.m "$SRC"/Redesigned/Kit/SGRHeaderInfo.m \
    "$SRC"/Settings/SGPage.m "$SRC"/Settings/SGPageStyle.m "$SRC"/Settings/SGModPage.m "$SRC"/Settings/SGGlowSwitch.m \
    "$SRC"/Redesigned/Kit/SGRAppearanceSettings.m \
    "$SRC"/Redesigned/Kit/SGRedesign.m "$SRC"/Redesigned/Kit/SGRNativeTheme.m \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework CoreImage -framework Foundation -framework Symbols \
    "$OUT/AppearanceHarness.app/Frameworks/NativeThemeFixture.dylib" -Wl,-rpath,@executable_path/Frameworks \
    -o "$OUT/AppearanceHarness.app/AppearanceHarness"

cat > "$OUT/AppearanceHarness.app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>AppearanceHarness</string>
<key>CFBundleIdentifier</key><string>com.vojta.appearanceharness</string>
<key>CFBundleName</key><string>AppearanceHarness</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>

<key>UILaunchScreen</key><dict/>
<key>UIApplicationSceneManifest</key><dict>
  <key>UIApplicationSupportsMultipleScenes</key><false/>
</dict>
</dict></plist>
PLIST
echo "built $OUT/AppearanceHarness.app"
