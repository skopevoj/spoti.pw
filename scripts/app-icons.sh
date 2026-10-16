#!/usr/bin/env bash
# Puts the mod's app icons (icons/*.icon) into a built IPA as alternate icons, for Mod > App icon.
#
#   scripts/app-icons.sh <out.ipa>   (pipeline.sh runs it)
#
# Each icon is an Icon Composer document without its artwork: the Spotify logo is read out of the IPA's own
# asset catalog, so the repo carries none of Spotify's. actool compiles the icons, car-tool.m merges their
# Liquid Glass stacks into Spotify's Assets.car (no flattened fallbacks, so iOS 26 and up draws them),
# CFBundleAlternateIcons lists them, and a 60 pt picture of each goes to SGAppIconPreviews/ for the list.
# Spotify.icon is the stock icon's look, drawn for its picture only.
#
# Without Xcode 26's Icon Composer, or without the logo in a later Spotify, the IPA is left as it was and
# the setting is not offered.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$1"
OUT_ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
APP_DIR="$(unzip -Z1 "$OUT" | grep -oE '^Payload/[^/]+\.app/' | sort -u | head -1)"
ICTOOL="$(xcode-select -p 2>/dev/null)/../Applications/Icon Composer.app/Contents/Executables/ictool"

skip() { echo "    $1: no alternate app icons in this build"; exit 0; }
[ -x "$ICTOOL" ] || skip "no Icon Composer (Xcode 26 or newer)"
xcrun --find actool >/dev/null 2>&1 || skip "no actool"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
unzip -q "$OUT" "${APP_DIR}Assets.car" "${APP_DIR}Info.plist" -d "$WORK"
CAR="$WORK/${APP_DIR}Assets.car"
PLIST="$WORK/${APP_DIR}Info.plist"

xcrun clang -fobjc-arc -framework Foundation -F/System/Library/PrivateFrameworks -framework CoreUI -lcompression \
  "$ROOT/scripts/car-tool.m" -o "$WORK/car-tool" 2>/dev/null || skip "car-tool did not build"
"$WORK/car-tool" svg "$CAR" AppIcon_Assets/Logo "$WORK/Logo.svg" || skip "no logo in Spotify's icon"

NAMES=()
PREVIEWS="$WORK/${APP_DIR}SGAppIconPreviews"
mkdir -p "$PREVIEWS" "$WORK/art"
for TEMPLATE in "$ROOT"/icons/*.icon; do
  NAME="$(basename "$TEMPLATE" .icon)"
  cp -R "$TEMPLATE" "$WORK/art/$NAME.icon"
  mkdir -p "$WORK/art/$NAME.icon/Assets"
  cp "$WORK/Logo.svg" "$WORK/art/$NAME.icon/Assets/Logo.svg"
  "$ICTOOL" "$WORK/art/$NAME.icon" --export-image --output-file "$PREVIEWS/$NAME.png" --platform iOS \
    --rendition Default --width 60 --height 60 --scale 3 >/dev/null 2>&1 || skip "ictool could not draw $NAME"
  [ "$NAME" = Spotify ] || NAMES+=("$NAME")
done

# An asset's identifier in the catalog is a hash of its name, and one already taken by Spotify's makes
# car-tool refuse (exit 3), so the icons are compiled again under a suffix until none collides. The keys
# of CFBundleAlternateIcons, the names the app asks for, stay SGAppIcon<Name> whatever the suffix.
MERGED=0
for SUFFIX in "" 2 3 4 5 6 7 8; do
  rm -rf "$WORK/src" "$WORK/car" && mkdir -p "$WORK/src" "$WORK/car"
  ARGS=()
  for NAME in "${NAMES[@]}"; do
    cp -R "$WORK/art/$NAME.icon" "$WORK/src/SGAppIcon$NAME$SUFFIX.icon"
    ARGS+=("$WORK/src/SGAppIcon$NAME$SUFFIX.icon" --alternate-app-icon "SGAppIcon$NAME$SUFFIX")
  done
  xcrun actool "${ARGS[@]}" --compile "$WORK/car" --platform iphoneos --minimum-deployment-target 26.0 \
    --target-device iphone --target-device ipad --include-all-app-icons --output-format human-readable-text > "$WORK/actool.log" 2>&1 \
    && [ -f "$WORK/car/Assets.car" ] || { cat "$WORK/actool.log" >&2; skip "actool failed"; }
  cp "$CAR" "$WORK/merged.car"
  STATUS=0
  "$WORK/car-tool" merge "$WORK/merged.car" "$WORK/car/Assets.car" >/dev/null || STATUS=$?
  [ "$STATUS" = 3 ] && continue
  [ "$STATUS" = 0 ] || skip "car-tool could not merge the icons"
  MERGED=1
  break
done
[ "$MERGED" = 1 ] || skip "every name collided with one of Spotify's"
xcrun assetutil -U "$WORK/merged.car" -o "$WORK/indexed.car" >/dev/null
xcrun assetutil -Z "$WORK/indexed.car" >/dev/null || skip "the merged catalog did not validate"
mv "$WORK/indexed.car" "$CAR"

python3 - "$PLIST" "$SUFFIX" "${NAMES[@]}" <<'EOF'
import plistlib, sys
path, suffix, names = sys.argv[1], sys.argv[2], sys.argv[3:]
with open(path, "rb") as f:
    info = plistlib.load(f)
alternates = {f"SGAppIcon{n}": {"CFBundleIconName": f"SGAppIcon{n}{suffix}"} for n in names}
for key in ("CFBundleIcons", "CFBundleIcons~ipad"):
    info.setdefault(key, {})["CFBundleAlternateIcons"] = alternates
with open(path, "wb") as f:
    plistlib.dump(info, f, fmt=plistlib.FMT_BINARY)
EOF

(cd "$WORK" && zip -q "$OUT_ABS" "${APP_DIR}Assets.car" "${APP_DIR}Info.plist" "${APP_DIR}SGAppIconPreviews/"*.png)
echo "    ${NAMES[*]}${SUFFIX:+ (compiled as SGAppIcon<Name>$SUFFIX)}"
