#!/bin/sh
set -eu
DEVICE=${1:?Usage: run-centering.sh SIMULATOR_UDID}
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
mkdir -p "$HERE/build/$DEVICE"
for entity in album artist; do
 case $entity in album) app=AlbumHarness;; artist) app=ArtistHarness;; esac
 xcrun simctl install "$DEVICE" "$HERE/../$entity/build/$app.app"
 log="$HERE/build/$DEVICE/$entity.log"
 launch=$(xcrun simctl launch --terminate-running-process "$DEVICE" "com.vojta.${entity}harness" centering)
 pid=${launch##*: }
 count=0
 while :; do
  xcrun simctl spawn "$DEVICE" log show --last 1m --style compact \
   --predicate "processIdentifier == $pid AND eventMessage CONTAINS 'entity centering checks:'" > "$log" 2>/dev/null
  if grep -q 'entity centering checks:' "$log"; then break; fi
  count=$((count+1)); [ "$count" -lt 30 ] || { cat "$log"; exit 1; }; sleep 1
 done
 grep 'entity centering checks:' "$log"
 xcrun simctl terminate "$DEVICE" "com.vojta.${entity}harness"
 grep -q 'entity centering checks:.* -- PASS' "$log"
done
