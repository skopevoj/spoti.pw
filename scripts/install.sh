#!/usr/bin/env bash
# Signs an IPA with your own certificate and installs it on the iPhone plugged into this Mac.
#
#   scripts/install.sh out/spoti.pw-0.20.0.ipa
#
# Put the certificate details in .signing.env (gitignored):
#   SIGN_P12=/path/to/cert.p12
#   SIGN_PROFILE=/path/to/profile.mobileprovision
#   SIGN_P12_PASSWORD=...
# WIFI=1 installs over Wi-Fi instead of USB (the phone must be paired for wireless sync).
# DEVICE_UDID selects one paired phone explicitly, so a connected iPad is never chosen instead.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "$ROOT/.signing.env" ] && . "$ROOT/.signing.env"
cd "$ROOT"
: "${SIGN_P12:?set SIGN_P12 in .signing.env}" "${SIGN_PROFILE:?set SIGN_PROFILE in .signing.env}" "${SIGN_P12_PASSWORD:?set SIGN_P12_PASSWORD in .signing.env}"

IN="${1:?usage: $0 <ipa>}"
SIGNED="${IN%.ipa}-signed.ipa"

command -v zsign >/dev/null || { echo "missing zsign -> brew install zsign" >&2; exit 1; }
command -v ideviceinstaller >/dev/null || { echo "missing ideviceinstaller -> brew install ideviceinstaller" >&2; exit 1; }

# The bundle id has to equal the App ID of the profile. iOS may well install a mismatched pair, but
# MediaRemote launches the now playing app by its application-identifier entitlement rather than by
# CFBundleIdentifier, so tapping the lock screen card then asks for a bundle that does not exist and
# nothing opens. A wildcard App ID needs no rewrite: the entitlement takes the IPA's own bundle id.
PROFILE_PLIST="$(mktemp)"
security cms -D -i "$SIGN_PROFILE" > "$PROFILE_PLIST" 2>/dev/null
APP_ID="$(plutil -extract Entitlements.application-identifier raw -o - "$PROFILE_PLIST" 2>/dev/null || true)"
rm -f "$PROFILE_PLIST"
APP_ID="${APP_ID#*.}"

sign() {  # sign [bundle id]
  echo "==> signing${1:+ as $1}"
  zsign -k "$SIGN_P12" -p "$SIGN_P12_PASSWORD" -m "$SIGN_PROFILE" ${1:+-b "$1"} -z 1 -o "$SIGNED" "$IN" >/dev/null
}

if [ -n "$APP_ID" ] && [ "$APP_ID" != "*" ]; then sign "$APP_ID"; else sign; fi
INSTALL_ARGS=(install "$SIGNED")
[ -z "${DEVICE_UDID:-}" ] || INSTALL_ARGS=(-u "$DEVICE_UDID" "${INSTALL_ARGS[@]}")
[ -z "${WIFI:-}" ] || INSTALL_ARGS=(-n "${INSTALL_ARGS[@]}")
echo "==> installing $SIGNED${DEVICE_UDID:+ on $DEVICE_UDID}"
ideviceinstaller "${INSTALL_ARGS[@]}" 2>&1 | tail -3
