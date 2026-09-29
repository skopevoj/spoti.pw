#!/bin/sh
# Builds the lock artwork harness for the Mac: the tweak's own SGArtworkFile.m, SGCanvas.m,
# LockScreenArtwork.m and the protobuf reader they share, with main.m driving them.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$HERE/../../tweak/Sources
mkdir -p "$HERE/build"
xcrun clang -fobjc-arc -g -O1 -mmacosx-version-min=26.0 \
    -I"$HERE/include" -I"$SRC" \
    -framework Foundation -framework AppKit -framework AVFoundation -framework CoreMedia \
    -framework CoreVideo -framework MediaPlayer \
    "$HERE/main.m" \
    "$SRC/Shared/LockScreenArtwork/LockScreenArtwork.m" \
    "$SRC/Shared/LockScreenArtwork/SGArtworkFile.m" \
    "$SRC/Shared/LockScreenArtwork/SGCanvas.m" \
    "$SRC/Shared/Lyrics/Protobuf.m" \
    -o "$HERE/build/lockart"
