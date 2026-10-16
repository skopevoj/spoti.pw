#!/bin/sh
# Runs Shared/LyricsSources/SpicyLyrics.m on the Mac against replies of the documented shapes, with
# the real line model (KaraokeTiming.m) and SGTTML.m's text compare under it.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$HERE/../../tweak/Sources
OUT=$HERE/build
mkdir -p "$OUT"

clang -fobjc-arc -g -O0 -Wall -Werror -DSG_VERSION='"harness"' -o "$OUT/spicytest" \
    "$HERE/main.m" "$HERE/stubs.m" "$SRC/Shared/LyricsSources/SpicyLyrics.m" \
    "$SRC/Shared/LyricsSources/SGTTML.m" "$SRC/Shared/Lyrics/KaraokeTiming.m" "$SRC/Shared/Lyrics/Protobuf.m" \
    -I"$HERE/include" -I"$SRC" -I"$SRC/Shared/LyricsSources" -I"$SRC/Shared/Lyrics" \
    -framework Foundation

cd "$HERE/fixtures" && "$OUT/spicytest"
