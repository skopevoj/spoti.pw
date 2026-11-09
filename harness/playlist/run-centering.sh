#!/bin/sh
# Run the production header hooks and Kit views on a native Duo or ordinary-phone simulator.
set -eu
DEVICE=${1:?Usage: run-centering.sh SIMULATOR_UDID}
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
LOGS="$HERE/build/centering-logs/$DEVICE"
mkdir -p "$LOGS"
xcrun simctl install "$DEVICE" "$HERE/build/PlaylistHarness.app"
for variant in liked own other mix; do
    log="$LOGS/$variant.log"
    launch=$(xcrun simctl launch --terminate-running-process \
        "$DEVICE" com.vojta.playlistharness "$variant" centering)
    pid=${launch##*: }
    count=0
    while :; do
        xcrun simctl spawn "$DEVICE" log show --last 1m --style compact \
            --predicate "processIdentifier == $pid AND eventMessage CONTAINS 'centering checks:'" > "$log" 2>/dev/null
        if grep -q 'centering checks:' "$log"; then break; fi
        count=$((count + 1))
        if [ "$count" -ge 30 ]; then
            echo "Timed out waiting for $variant" >&2
            cat "$log" >&2
            exit 1
        fi
        sleep 1
    done
    grep 'centering checks:' "$log"
    grep -q 'centering checks:.* -- PASS' "$log"
done
xcrun simctl terminate "$DEVICE" com.vojta.playlistharness
echo 'All playlist header centering checks passed.'
