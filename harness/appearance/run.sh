#!/bin/sh
set -eu
DEVICE=${1:?Usage: run.sh SIMULATOR_UDID}
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
OUT=${OUT:-$HERE/build}
DATA=$(xcrun simctl list devices -j | python3 -c 'import json,sys; print(next(d["dataPath"] for ds in json.load(sys.stdin)["devices"].values() for d in ds if d["udid"]==sys.argv[1]))' "$DEVICE")
xcrun simctl install "$DEVICE" "$OUT/AppearanceHarness.app"
ORIGINAL=$(xcrun simctl ui "$DEVICE" appearance)
trap 'xcrun simctl ui "$DEVICE" appearance "$ORIGINAL" >/dev/null 2>&1 || true' EXIT
for CASE in dark light system-light system-dark invalid-mode nil-theme rejected-theme rejected-native default-light default-dark selector-dark selector-light; do
 MODE=0; NIL=; REJECT=; NATIVE_REJECT=; SELECTOR=
 case "$CASE" in light) MODE=1;; system-light) MODE=2; xcrun simctl ui "$DEVICE" appearance light;; system-dark) MODE=2; xcrun simctl ui "$DEVICE" appearance dark;; invalid-mode) MODE=99;; nil-theme) MODE=1; NIL=1;; rejected-theme) MODE=1; REJECT=1;; rejected-native) MODE=1; NATIVE_REJECT=1;; default-light) MODE=unset; xcrun simctl ui "$DEVICE" appearance light;; default-dark) MODE=unset; xcrun simctl ui "$DEVICE" appearance dark;; selector-dark) MODE=0; SELECTOR=1;; selector-light) MODE=1; SELECTOR=1;; esac
 NAME="appearance-$CASE-$$.log"
 SIMCTL_CHILD_SG_TEST_APPEARANCE="$MODE" SIMCTL_CHILD_SG_TEST_NIL_THEME="$NIL" SIMCTL_CHILD_SG_TEST_REJECT_THEME="$REJECT" SIMCTL_CHILD_SG_TEST_REJECT_NATIVE_THEME="$NATIVE_REJECT" SIMCTL_CHILD_SG_TEST_SELECTOR="$SELECTOR" \
 xcrun simctl launch --terminate-running-process --stderr="/tmp/$NAME" "$DEVICE" com.vojta.appearanceharness
 COUNT=0
 until grep -q 'APPEARANCE CHECKS:' "$DATA/tmp/$NAME" 2>/dev/null; do
  COUNT=$((COUNT+1)); [ "$COUNT" -lt 20 ] || { cat "$DATA/tmp/$NAME"; echo 'Appearance fixture timed out' >&2; exit 1; }; sleep 1
 done
 cp "$DATA/tmp/$NAME" "$OUT/$CASE.log"
 xcrun simctl io "$DEVICE" screenshot "$OUT/$CASE.png" >/dev/null
 xcrun simctl terminate "$DEVICE" com.vojta.appearanceharness
 grep 'APPEARANCE CHECKS:' "$OUT/$CASE.log"
 grep -q 'APPEARANCE CHECKS:.* -- PASS' "$OUT/$CASE.log"
done
