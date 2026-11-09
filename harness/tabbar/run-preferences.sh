#!/bin/sh
# Run only against dedicated simulators; never a physical device.
set -eu
PHONE=${1:?Usage: run-preferences.sh PHONE_SIMULATOR_UDID DUO_SIMULATOR_UDID}
DUO=${2:?Usage: run-preferences.sh PHONE_SIMULATOR_UDID DUO_SIMULATOR_UDID}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT="$ROOT/out/navbar-preferences-qa"
mkdir -p "$OUT"
THEOS=${THEOS:-$HOME/theos}; export THEOS
OUT="$OUT/build-phone" "$ROOT/harness/tabbar/build.sh" > "$OUT/build-phone.log" 2>&1
OUT="$OUT/build-duo" BUNDLE_ID=com.kyle.spotipw.duo "$ROOT/harness/tabbar/build.sh" > "$OUT/build-duo.log" 2>&1
# Refuse to replace a real app, even inside the simulator.
existing=$(xcrun simctl get_app_container "$DUO" com.kyle.spotipw.duo app 2>/dev/null || true)
if [ -n "$existing" ] && [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$existing/Info.plist")" != TabBarHarness ]; then
    echo 'Refusing to replace an existing non-fixture Duo app.' >&2
    exit 1
fi
run() {
    device=$1; bundle=$2; name=$3; mode=$4; theme=$5
    pid=$(xcrun simctl launch --terminate-running-process "$device" "$bundle" "$mode" "$theme" | awk '{print $NF}')
    sleep 11
    xcrun simctl spawn "$device" log show --last 2m --style compact --predicate "processID == $pid AND (eventMessage CONTAINS '[harness]' OR eventMessage CONTAINS '*** Assertion')" > "$OUT/$name.log"
    if grep -q '\*\*\* Assertion' "$OUT/$name.log"; then cat "$OUT/$name.log"; return 1; fi
    grep -q 'PASS 160 exact-bundle' "$OUT/$name.log"
    grep -q 'PASS saved tab order' "$OUT/$name.log"
    grep -q 'source-icon and semantic-label selection synchronization' "$OUT/$name.log"
    if [ "$mode" = reservation ]; then grep -q 'PASS reservation restored' "$OUT/$name.log"; fi
    if [ "$bundle" = com.kyle.spotipw.duo ]; then grep -q 'PASS live hinge label result' "$OUT/$name.log"; fi
    xcrun simctl terminate "$device" "$bundle"
    echo "PASS $name"
}
xcrun simctl install "$PHONE" "$OUT/build-phone/TabBarHarness.app"
xcrun simctl install "$DUO" "$OUT/build-phone/TabBarHarness.app"
xcrun simctl install "$DUO" "$OUT/build-duo/TabBarHarness.app"
(
    run "$PHONE" com.vojta.tabbarharness phone-dark cycle dark
    run "$PHONE" com.vojta.tabbarharness phone-light cycle light
) & phone_pid=$!
(
    run "$DUO" com.vojta.tabbarharness duo-original-dark reservation dark
    run "$DUO" com.vojta.tabbarharness duo-original-light cycle light
    run "$DUO" com.kyle.spotipw.duo duo-bundle-dark cycle dark
    run "$DUO" com.kyle.spotipw.duo duo-bundle-light reservation light
) & duo_pid=$!
result=0
wait "$phone_pid" || result=1
wait "$duo_pid" || result=1
exit "$result"
