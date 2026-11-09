# Album and artist header centering

Build `harness/album/build.sh` and `harness/artist/build.sh` with THEOS set, then run
`harness/entity-header/run-centering.sh SIMULATOR_UDID`. These harnesses compile the real
AlbumHeader/ArtistHeader hooks and shared Kit views; scene delegates permit iOS 27 launch.

Each entity runs 36 geometry cases plus one initial wrapping-title/hero check. Geometry covers
four synthetic window widths (Duo 466/669/951/466, phone 320/402/466/320), three host arrangements
(full width, translated 13pt, already inset), and three vertical states. Four repeated production
layout passes precede each check. Expected content is independently derived from the page's UIKit
safe-area layout guide, intersected with the host; ordinary phones retain full host width.
Assertions cover info bounds, title/meta and Play centers, all three controls fitting the column,
and the full-bleed hero ending 56pt below the laid-out title top. The Duo fixture title wraps at
the content width but not full header width, catching incorrect hero text-height measurement.
Album/artist have no descriptions; playlist's existing `other` variant covers description layout.

These are mock Spotify hierarchies and synthetic window resizes, not live Spotify, physical fold
transitions, or a test of Spotify's native navigation title. Continue to run the playlist's existing
`run-centering.sh` on Duo and phone to guard its previously verified alignment.
