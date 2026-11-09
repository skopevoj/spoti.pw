#!/bin/sh
# The strict pass target is a Duo simulator. Phone diagnostics retain known pre-edit failures.
set -eu
DEVICE=${1:?Usage: run.sh DUO_SIMULATOR_UDID}
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
xcrun simctl install "$DEVICE" "$HERE/build/EntityMenuHarness.app"
launch=$(xcrun simctl launch --terminate-running-process "$DEVICE" com.vojta.entitymenuharness)
pid=${launch##*: }
count=0
while :; do
    xcrun simctl spawn "$DEVICE" log show --last 1m --style compact \
        --predicate "processIdentifier == $pid" > "$HERE/build/last-run.log" 2>/dev/null
    if grep -q 'ENTITY MENU CHECKS:' "$HERE/build/last-run.log"; then break; fi
    count=$((count + 1))
    if [ "$count" -ge 30 ]; then echo 'Timed out waiting for entity menu checks' >&2; exit 1; fi
    sleep 1
done
grep 'ENTITY MENU CHECKS:' "$HERE/build/last-run.log"
xcrun simctl terminate "$DEVICE" com.vojta.entitymenuharness
grep -q 'ENTITY MENU CHECKS:.* -- PASS' "$HERE/build/last-run.log"
