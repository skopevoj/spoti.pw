# Lock artwork harness

`Shared/LockScreenArtwork` run on the Mac, which has the same MediaPlayer the lock screen wants.
It writes a real 720x1280 H.264 clip, the shape a Canvas is, puts the tweak's own `SGArtworkCrop`
over it and checks what comes out plays at 3:4 with the full width kept and is not encoded a second
time; hands the result to `MPMediaItemAnimatedArtwork` and puts it in the now playing info the way
the hook does; and checks the pure parts, `SGCanvasFromMetadata`, the `spotify.canvaz.cache` request
and answer, and `SGArtworkInInfo` keeping its key through the rewrites `LockScreenLyrics.x` makes of
the same dictionary, in either order the two hooks can run.

    ./build.sh && build/lockart

What it cannot show: a Mac answers `+[MPNowPlayingInfoCenter supportedAnimatedArtworkKeys]` with
nothing at all, so which key an iPhone offers, and whether the system then asks the handlers for the
still and the clip, is only visible on the phone.
