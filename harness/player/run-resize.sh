#!/bin/sh
# Run the real PlayerLyrics hook against shrinking/growing mocked player geometry.
set -eu
DEVICE=${1:?Usage: run-resize.sh SIMULATOR_UDID}
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
APP="$HERE/build/PlayerHarness.app"
LOGS="$HERE/build/resize-logs"
mkdir -p "$LOGS"
xcrun simctl install "$DEVICE" "$APP"
for size in 320x667 402x874 466x678 669x951 951x669; do
    log="$LOGS/$size.log"
    launch=$(SIMCTL_CHILD_HARNESS_SCENARIO=resize SIMCTL_CHILD_HARNESS_SIZE="$size" \
        xcrun simctl launch --terminate-running-process "$DEVICE" com.vojta.playerharness)
    pid=${launch##*: }
    count=0
    while :; do
        xcrun simctl spawn "$DEVICE" log show --last 1m --style compact \
            --predicate "processIdentifier == $pid AND eventMessage CONTAINS 'resize checks:'" > "$log" 2>/dev/null
        if grep -q 'resize checks:' "$log"; then break; fi
        count=$((count + 1))
        if [ "$count" -ge 30 ]; then
            echo "Timed out waiting for $size" >&2
            cat "$log" >&2
            exit 1
        fi
        sleep 1
    done
    grep 'resize checks:' "$log"
    grep -q 'resize checks:.* -- PASS' "$log"
done
# Keep the existing image-race/offline and scroll assertions in the same smoke run.
for scenario in artwork scroll; do
    log="$LOGS/$scenario.log"
    launch=$(SIMCTL_CHILD_HARNESS_SCENARIO="$scenario" \
        xcrun simctl launch --terminate-running-process "$DEVICE" com.vojta.playerharness)
    pid=${launch##*: }
    count=0
    while :; do
        xcrun simctl spawn "$DEVICE" log show --last 1m --style compact \
            --predicate "processIdentifier == $pid AND eventMessage CONTAINS '$scenario checks:'" > "$log" 2>/dev/null
        if grep -q "$scenario checks:" "$log"; then break; fi
        count=$((count + 1))
        if [ "$count" -ge 30 ]; then
            echo "Timed out waiting for $scenario" >&2
            cat "$log" >&2
            exit 1
        fi
        sleep 1
    done
    grep "$scenario checks:" "$log"
    grep -q "$scenario checks:.* -- PASS" "$log"
done
xcrun simctl terminate "$DEVICE" com.vojta.playerharness
echo 'All resize, artwork and scroll checks passed.'
