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
OUT="${OUT:-$ROOT/out/rokis.pw-$MOD_VERSION.ipa}"
echo "==> rokis.pw $MOD_VERSION on Spotify $SPOTIFY_VERSION -> $OUT"

# What CarPlay looks for, as it stands in an IPA: the app's CarPlay entitlements, which a signing tool
# keeps only where the profile allows them, and the CarPlay scene its Info.plist declares. Printed so a
# build log says why Spotify does or does not show up as a CarPlay app once signed.
carplay_report() {
  local ipa="$1" dir exec ents
  dir="$(mktemp -d)"
  unzip -p "$ipa" "${APP_DIR}Info.plist" > "$dir/Info.plist" 2>/dev/null || true
  exec="$(plutil -extract CFBundleExecutable raw -o - "$dir/Info.plist" 2>/dev/null || true)"
  if [ -n "$exec" ] && unzip -p "$ipa" "${APP_DIR}${exec}" > "$dir/bin" 2>/dev/null; then
    ents="$(ldid -e "$dir/bin" 2>/dev/null | grep -iE -A1 'carplay|playable-content' | grep -vE '^--$' || true)"
    echo "    entitlements: ${ents:-none for CarPlay}" | tr '\n\t' '  '
    echo
  fi
  echo "    scenes: $(plutil -p "$dir/Info.plist" 2>/dev/null | grep -oE '"(UISceneConfigurationName|UISceneDelegateClassName|UISceneClassName)" => "[^"]+"|"[A-Za-z]+SceneSessionRole[A-Za-z]+"' | tr '\n' ' ')"
  rm -rf "$dir"
}
echo "==> CarPlay in Spotify's IPA"
carplay_report "$IN"

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
  -install_name @rpath/SpotifyGlassAppGroups.dylib -o "$GROUPS_DYLIB" "$ROOT/extension/AppGroups/AppGroups.m" "$ROOT/extension/AppGroups/Keychain.m"
FILES+=("$GROUPS_DYLIB")

echo "==> injecting"
# -w drops the Watch app: its companion-app key would still name com.spotify.client and block the install.
unzip -p "$IN" "${APP_DIR}Info.plist" > "$ROOT/out/.info.plist"
python3 "$ROOT/scripts/merge-local-network-plist.py" "$ROOT/out/.info.plist" \
  "$ROOT/plist/liquid-glass.plist" "$ROOT/out/.injection.plist"
rm -f "$ROOT/out/.info.plist"
cyan -i "$IN" -o "$OUT" -f "${FILES[@]}" -l "$ROOT/out/.injection.plist" ${BUNDLE_ID:+-b "$BUNDLE_ID"} ${NAME:+-n "$NAME"} ${ICON:+-k "$ICON"} -w -s --overwrite
rm -f "$ROOT/out/.injection.plist"

# Siri's requests are answered by Spotify's Intents extension, not by the app, and it finds the signed
# in account through the same App Groups the widget reads: re-signed, it saw an empty group and Siri
# answered that you need to log in to Spotify. Every extension that serves the widget or Siri gets the
# shim, so their groups land on the one the app writes to.
echo "==> loading the App Group shim in the widget and Siri extensions"
OUT_ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
PATCHED=0
# SG_DISABLE=extpatch leaves them as cyan made them (Core/SGPrefs.h says what SG_DISABLE is).
case ",${SG_DISABLE:-}," in *,extpatch,*) APPEXES="" ;; *) APPEXES="$(unzip -Z1 "$OUT" | grep -oE "^${APP_DIR}PlugIns/[^/]+\.appex/" | sort -u)" ;; esac
for APPEX in $APPEXES; do
  # Spotify's own extensions only: the mod's Live Activity widget has no App Groups of Spotify's to move.
  case "$(basename "$APPEX")" in SpotifyGlass*) continue ;; esac
  PATCH="$(mktemp -d)"
  unzip -q "$OUT" "${APPEX}Info.plist" -d "$PATCH"
  POINT="$(plutil -extract NSExtension.NSExtensionPointIdentifier raw -o - "$PATCH/${APPEX}Info.plist" 2>/dev/null || true)"
  EXEC="$(plutil -extract CFBundleExecutable raw -o - "$PATCH/${APPEX}Info.plist" 2>/dev/null || true)"
  case "$POINT" in
    com.apple.widgetkit-extension|com.apple.intents-service|com.apple.intents-ui-service) ;;
    *) rm -rf "$PATCH"; continue ;;
  esac
  BIN="${APPEX}${EXEC}"
  if [ -z "$EXEC" ] || ! unzip -q "$OUT" "$BIN" -d "$PATCH" 2>/dev/null; then rm -rf "$PATCH"; continue; fi
  echo "    $(basename "$APPEX") ($POINT)"
  "$ROOT/scripts/insert-dylib.py" "$PATCH/$BIN" @rpath/SpotifyGlassAppGroups.dylib
  # Fakesigned again with its own entitlements, the way cyan -s left it, for TrollStore.
  ldid -e "$PATCH/$BIN" > "$PATCH/ents.plist" 2>/dev/null || true
  if [ -s "$PATCH/ents.plist" ]; then ldid -S"$PATCH/ents.plist" "$PATCH/$BIN"; else ldid -S "$PATCH/$BIN"; fi
  (cd "$PATCH" && zip -q "$OUT_ABS" "$BIN")
  rm -rf "$PATCH"
  PATCHED=$((PATCHED + 1))
done
[ "$PATCHED" -gt 0 ] || echo "    no widget or Siri extension in this IPA"

echo "==> adding the alternate app icons"
# A failure leaves the IPA as it was, without them; Mod > App icon then does not show.
"$ROOT/scripts/app-icons.sh" "$OUT" || echo "    the app icons failed: building without them"

echo "==> CarPlay in the built IPA"
carplay_report "$OUT"

if [ -n "${EXT_DIR:-}" ]; then
  echo "==> adding the Live Activity intents to Spotify's App Intents metadata"
  "$ROOT/scripts/merge-appintents.py" "$OUT" "$APP_DIR" "$EXT_DIR/app/Metadata.appintents"
fi

echo "==> done: $OUT"
[ "$INSTALL" = 1 ] && exec "$ROOT/scripts/install.sh" "$OUT"
exit 0
