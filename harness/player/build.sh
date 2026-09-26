#!/bin/sh
set -e
# SRC may point at another checkout of tweak/Sources (an older commit, to see a bug before its fix).
SRC=${SRC:-$(cd "$(dirname "$0")/../../tweak/Sources" && pwd)}
OUT=${OUT:-$(dirname "$0")/build}
rm -rf "$OUT"; mkdir -p "$OUT/gen" "$OUT/PlayerHarness.app"

for f in Redesigned/Player/PlayerLyrics.x Redesigned/Player/PlayerArtwork.x Redesigned/Player/PlayerFooter.x \
         Redesigned/Player/PlayerScroll.x Redesigned/Player/PlayerField.x Redesigned/Kit/SGRBridges.x; do
    name=$(basename "$f" .x)
    "$THEOS/bin/logos.pl" -c generator=internal "$SRC/$f" > "$OUT/gen/$name.m"
done

SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun -sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -fobjc-arc -g -O0 \
    -I"$SRC" -I"$SRC/Redesigned/Player" -I"$SRC/Redesigned/Kit" -I"$OUT/gen" -isysroot "$SDK" \
    -Wno-deprecated-declarations \
    "$(dirname "$0")/main.m" "$(dirname "$0")/stubs.m" \
    "$OUT"/gen/*.m \
    "$SRC"/Core/SGLog.m "$SRC"/Core/SGPrefs.m "$SRC"/Core/SGViewTree.m "$SRC"/Core/SGGlass.m \
    "$SRC"/Core/SGBackdrop.m "$SRC"/Core/SGFlagForce.m "$SRC"/Core/SGUIMode.m \
    "$SRC"/Redesigned/Kit/SGRTokens.m "$SRC"/Redesigned/Kit/SGRPalette.m "$SRC"/Redesigned/Kit/SGRField.m "$SRC"/Redesigned/Kit/SGRFlow.m \
    "$SRC"/Redesigned/Kit/SGRGlass.m "$SRC"/Redesigned/Kit/SGRGlyph.m "$SRC"/Redesigned/Kit/SGRRestyle.m \
    "$SRC"/Redesigned/Kit/SGRedesign.m \
    "$SRC"/Redesigned/Lyrics/SGRLyricsImmersive.m "$SRC"/Redesigned/Lyrics/SGRImmersiveState.m "$SRC"/Redesigned/Lyrics/SGRSingControl.m \
    "$(dirname "$0")/../lyrics-immersive/sing_stubs.m" \
    "$SRC"/Redesigned/Lyrics/SGRKaraokeView.m "$SRC"/Redesigned/Lyrics/LyricsText.m "$SRC"/Shared/Lyrics/KaraokeTiming.m "$SRC"/Shared/Lyrics/Protobuf.m \
    -framework AVFoundation -framework UIKit -framework QuartzCore -framework CoreGraphics -framework CoreImage -framework Foundation -framework Symbols \
    -o "$OUT/PlayerHarness.app/PlayerHarness"

cat > "$OUT/PlayerHarness.app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>PlayerHarness</string>
<key>CFBundleIdentifier</key><string>com.vojta.playerharness</string>
<key>CFBundleName</key><string>PlayerHarness</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>UIUserInterfaceStyle</key><string>Dark</string>
<key>UILaunchScreen</key><dict/>
<key>UIApplicationSceneManifest</key><dict>
  <key>UIApplicationSupportsMultipleScenes</key><false/>
</dict>
</dict></plist>
PLIST
echo "built $OUT/PlayerHarness.app"
