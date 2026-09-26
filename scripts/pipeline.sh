#!/usr/bin/env bash
# Builds the spotifyglass tweak and injects it (plus FLEX) into a decrypted Spotify IPA.
#
#   scripts/pipeline.sh <decrypted.ipa> [-o out.ipa] [--no-flex] [--install] [--name N] [--icon P.png]   (or: make build / make install)
#
# --install hands the result to install.sh (sign with your certificate, push to the plugged-in iPhone).
#
# The IPA is yours to supply: drop a decrypted Spotify .ipa in ipa/ and the Makefile finds it.
#
# Needs: Theos in $THEOS (default ~/theos), an iPhoneOS 26+ SDK from the selected Xcode or in $THEOS/sdks,
# gmake, ldid, dpkg-deb (brew) and cyan (uv tool install "cyan @ git+https://github.com/asdfzxcvbn/pyzule-rw").
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THEOS="${THEOS:-$HOME/theos}"
FLEX_DEB="$ROOT/vendor/com.hopeless.autoflex_0.0.1_iphoneos-arm.deb"
# The bundle id is left alone by default, the way EeveeSpotify and the YouTube mods leave it. Rewriting
# it only works when it ends up equal to the App ID of the profile that signs the IPA, and this build
# has no idea what that profile will be -- it is picked later, in Feather or whatever else the person
# signing uses. A mismatched pair still installs, but MediaRemote launches the now playing app by its
# application-identifier entitlement, so tapping the lock screen card asks for a bundle that does not
# exist and nothing opens. Set BUNDLE_ID only if you know it matches your App ID; scripts/install.sh
# reads that App ID out of the profile and can do it safely.
BUNDLE_ID="${BUNDLE_ID:-}"
mkdir -p "$ROOT/out"

IN="" OUT="" WITH_FLEX=1 INSTALL=0 NAME="" ICON=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) OUT="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --icon) ICON="$2"; shift 2 ;;
    --no-flex) WITH_FLEX=0; shift ;;
    --install) INSTALL=1; shift ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) IN="$1"; shift ;;
  esac
done
[ -n "$IN" ] || { echo "no IPA: put a decrypted Spotify .ipa in ipa/, or pass one (make build IPA=path.ipa)" >&2; exit 1; }
[ -f "$IN" ] || { echo "no such file: $IN" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing $1 -> $2" >&2; exit 1; }; }
need gmake "brew install make"
need ldid "brew install ldid"
need dpkg-deb "brew install dpkg"
need cyan "uv tool install 'cyan @ git+https://github.com/asdfzxcvbn/pyzule-rw'"
{ ls -d "$THEOS"/sdks/iPhoneOS*.sdk "$(xcode-select -p 2>/dev/null)"/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS*.sdk 2>/dev/null || true; } \
  | grep -qE 'iPhoneOS(2[6-9]|[3-9][0-9])\.' \
  || { echo "no iPhoneOS 26+ SDK: xcode-select an Xcode 26 or newer, or put the SDK in $THEOS/sdks" >&2; exit 1; }
# cyan skips -k with only a warning when its environment has no Pillow.
if [ -n "$ICON" ]; then
  [ -f "$ICON" ] || { echo "no such icon: $ICON" >&2; exit 1; }
  "$(dirname "$(readlink -f "$(command -v cyan)")")/python" -c 'import PIL' 2>/dev/null \
    || { echo "cyan has no Pillow for --icon -> uv tool install --force --with pillow 'cyan @ git+https://github.com/asdfzxcvbn/pyzule-rw'" >&2; exit 1; }
fi

APP_DIR="$(unzip -Z1 "$IN" | grep -oE '^Payload/[^/]+\.app/' | sort -u | head -1)"
[ -n "$APP_DIR" ] || { echo "no Payload/*.app in $IN" >&2; exit 1; }
SPOTIFY_VERSION="$(unzip -p "$IN" "${APP_DIR}Info.plist" > "$ROOT/out/.info.plist" && plutil -extract CFBundleShortVersionString raw -o - "$ROOT/out/.info.plist")"
rm -f "$ROOT/out/.info.plist"
# The name carries the mod's version, not Spotify's: it is the one the About page shows and the one
# worth telling builds apart by. version.txt is read the way tweak/Makefile reads it, so a build from
# a fork left behind by a release is named for the version it really is.
MOD_VERSION="$(cat "$ROOT/version.txt" 2>/dev/null || true)"
: "${MOD_VERSION:=0.0.0}"
OUT="${OUT:-$ROOT/out/spoti.pw-$MOD_VERSION.ipa}"
echo "==> spoti.pw $MOD_VERSION on Spotify $SPOTIFY_VERSION -> $OUT"

# The flag table is generated rather than committed, so it always matches the IPA being built.
if [ ! -f "$ROOT/tweak/Sources/Shared/Flags/SGFlagList.m" ]; then
  echo "==> extracting the flag table (once, about 40 s)"
  "$ROOT/scripts/extract-flags.py" "$IN"
fi

echo "==> building tweak"
export THEOS
# Theos resolves its toolchain through `xcrun -sdk iphoneos`, which needs full Xcode. With only the
# Command Line Tools installed, name the tools directly instead.
if ! xcrun -sdk iphoneos --find clang >/dev/null 2>&1; then
  export TARGET_CC=clang TARGET_CXX=clang++ TARGET_LD=clang++ \
         TARGET_STRIP=strip TARGET_LIPO=lipo TARGET_CODESIGN_ALLOCATE=codesign_allocate TARGET_LIBTOOL=libtool
fi
# Theos builds its Swift support tools only at MAKELEVEL 0, and `make release` hands this script MAKELEVEL 1.
env -u MAKELEVEL gmake -C "$ROOT/tweak" clean package >/dev/null
TWEAK_DEB="$(ls -t "$ROOT"/tweak/packages/*.deb | head -1)"
echo "    $TWEAK_DEB"

FILES=("$TWEAK_DEB")
# Optional local voice model, produced by harness/sing/package_model.py. No download at build or
# playback time. Without this resource Sing remains unavailable and its setting defaults off.
if [ -n "${SING_MODEL_BUNDLE:-}" ]; then
  { [ -d "$SING_MODEL_BUNDLE/separator.aimodelc" ] || [ -d "$SING_MODEL_BUNDLE/separator.mlmodelc" ]; } \
    && [ -f "$SING_MODEL_BUNDLE/hashes.json" ] && [ -f "$SING_MODEL_BUNDLE/Sing.plist" ] \
    || { echo "invalid SING_MODEL_BUNDLE: package the local compiled model first" >&2; exit 1; }
  FILES+=("$SING_MODEL_BUNDLE")
fi
[ "$WITH_FLEX" = 1 ] && FILES+=("$FLEX_DEB")

# The Live Activity (Shared/LiveActivity) draws in a widget extension of its own.
if xcrun --sdk iphoneos --find swiftc >/dev/null 2>&1; then
  EXT_DIR="$ROOT/out/extension"
  unzip -p "$IN" "${APP_DIR}Info.plist" > "$ROOT/out/.info.plist"
  "$ROOT/scripts/build-extension.sh" "$ROOT/out/.info.plist" "$EXT_DIR"
  rm -f "$ROOT/out/.info.plist"
  FILES+=("$EXT_DIR/SpotifyGlassLiveActivity.appex")
else
  echo "==> no Xcode selected: building without the Live Activity extension"
fi

# Spotify's widget reads what the app writes through App Group suites the re-signed IPA is not entitled
# to; this dylib, loaded by the app and by the widget, puts both on a group the signature does have.
echo "==> building the App Group shim"
GROUPS_DYLIB="$ROOT/out/SpotifyGlassAppGroups.dylib"
xcrun --sdk iphoneos clang -target arm64-apple-ios16.0 -dynamiclib -fobjc-arc -Os -framework Foundation -framework Security \
  -install_name @rpath/SpotifyGlassAppGroups.dylib -o "$GROUPS_DYLIB" "$ROOT/extension/AppGroups/AppGroups.m"
FILES+=("$GROUPS_DYLIB")

echo "==> injecting"
# -w drops the Watch app: its companion-app key would still name com.spotify.client and block the install.
cyan -i "$IN" -o "$OUT" -f "${FILES[@]}" -l "$ROOT/plist/liquid-glass.plist" ${BUNDLE_ID:+-b "$BUNDLE_ID"} ${NAME:+-n "$NAME"} ${ICON:+-k "$ICON"} -w -s --overwrite

echo "==> loading the App Group shim in the home screen widget"
WIDGET_BIN="${APP_DIR}PlugIns/WidgetExtension.appex/WidgetExtension"
if unzip -l "$OUT" "$WIDGET_BIN" >/dev/null 2>&1; then
  PATCH="$(mktemp -d)"
  unzip -q "$OUT" "$WIDGET_BIN" -d "$PATCH"
  "$ROOT/scripts/insert-dylib.py" "$PATCH/$WIDGET_BIN" @rpath/SpotifyGlassAppGroups.dylib
  # Fakesigned again with its own entitlements, the way cyan -s left it, for TrollStore.
  ldid -e "$PATCH/$WIDGET_BIN" > "$PATCH/ents.plist"
  ldid -S"$PATCH/ents.plist" "$PATCH/$WIDGET_BIN"
  OUT_ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
  (cd "$PATCH" && zip -q "$OUT_ABS" "$WIDGET_BIN")
  rm -rf "$PATCH"
else
  echo "    no WidgetExtension.appex in this IPA"
fi

if [ -n "${EXT_DIR:-}" ]; then
  echo "==> adding the Live Activity intents to Spotify's App Intents metadata"
  "$ROOT/scripts/merge-appintents.py" "$OUT" "$APP_DIR" "$EXT_DIR/app/Metadata.appintents"
fi

python3 "$ROOT/harness/sing/configure_background.py" "$OUT"

echo "==> done: $OUT"
[ "$INSTALL" = 1 ] && exec "$ROOT/scripts/install.sh" "$OUT"
exit 0
