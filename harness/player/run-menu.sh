#!/bin/sh
# Real native bar-region, hit-test, action and restoration checks on each supplied simulator.
set -eu
[ "$#" -gt 0 ] || { echo 'Usage: run-menu.sh SIMULATOR_UDID [SIMULATOR_UDID ...]' >&2; exit 1; }
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
mkdir -p "$HERE/build/menu-logs"
for device in "$@"; do
    xcrun simctl install "$device" "$HERE/build/PlayerHarness.app"
    launch=$(SIMCTL_CHILD_HARNESS_SCENARIO=menu xcrun simctl launch --terminate-running-process "$device" com.vojta.playerharness)
    pid=${launch##*: }
    log="$HERE/build/menu-logs/$device.log"
    count=0
    while :; do
        sleep 1
        xcrun simctl spawn "$device" log show --last 1m --style compact \
            --predicate "processIdentifier == $pid AND eventMessage CONTAINS 'menu checks:'" > "$log" 2>/dev/null
        if grep -q 'menu checks:' "$log"; then break; fi
        count=$((count + 1))
        [ "$count" -lt 20 ] || { echo "Timed out on $device" >&2; exit 1; }
    done
    grep 'menu checks:' "$log"
    grep -q 'menu checks:.* -- PASS' "$log"
    xcrun simctl terminate "$device" com.vojta.playerharness
 done
