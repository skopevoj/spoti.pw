# Album credits and discovery — issues #118 and #119

Branch: `codex/album-118-119-beta`, based on upstream `beta` at
`49e02e204f397b1e4197876dd622d4ee1663188e`. Only the two album issue commits are applied
on top of that base; upstream beta's own lyrics and audio implementation stays unchanged.

## Behavior

- Redesign only. Native pages keep Spotify's original artist lines and layout.
- Hide a track's artist text when it matches the album artist. Also hide it when additional
  artists exactly match an explicit `feat.`, `ft.`, `featuring` or `with` title suffix.
- Normalize the header's bullet-separated co-artists to the track credit's comma separators,
  including albums with three or more artists. Retain subset credits and additional guests.
- Keep missing, ambiguous and compilation credits. Normalize case, whitespace and Unicode
  composition; do not strip accents or split artist names at ampersands/slashes.
- Keep Spotify's row height, fonts, explicit/download badges, actions and combined accessibility
  labels. Centre the title and show the explicit badge inline after it, reserving text width so long
  titles cannot overlap the badges or menu. Mirror the arrangement for RTL. Restore presentation on reuse.
- Restore the entire Spotify footer in its supplied order, including More by, Related Music Videos,
  You might also like, concerts and merch. Keep original links, carousels, spacer heights and copyright.
- Clear the retained base surface on album discovery cards and plain playlist recommendation cells,
  so captions and headings sit directly on the artwork field. Preserve artwork and badge paint.

## Design review

The Apple HIG skill's `lists-and-tables.md > Content` supports concise row text;
`accessibility.md > Mobility` and `typography.md > Supporting Dynamic Type` support retaining
Spotify's measured controls and text. `collections.md > Platform considerations` favors stable
layout while browsing. Apple Design's simplicity/agency guidance supports restoring discovery.
The Liquid Glass skill keeps glass on navigation and controls, so no glass was added to list content.
No new animation is introduced; the existing scrolling and transitions remain Spotify's.

## Beta migration, 2026-09-28

- Cherry-picked the issue implementation (`5b46aec`) and discovery-background follow-up (`604e4a5`)
  as two commits directly above the requested upstream beta commit. The old branch is preserved.
- Resolved conflicts while keeping beta's animated album covers, artist facepile, page reveal
  readiness and updated harness dependencies. Artist metadata is handed to the credit policy
  alongside beta's existing header setup; rows still mark the page's list ready.
- The production diff from beta is limited to the album header/credit/section files and playlist
  footer cleanup. No Shared, Lyrics, Player, Kit, signing or version files are changed by this port.
- Full arm64 Theos package build and import-layer checks passed.
- All 490 simulator checks passed again: 172 redesign, 146 native and 172 late-header checks.
  Inspected the settled simulator screen: the artist face remains visible, redundant row credits
  are hidden, explicit badges are inline and the uncredited guest retains its subtitle.
- Packaged and signed the beta-based build at `20dab49` from the supplied Spotify 9.1.78 IPA,
  then installed it on the iPhone 17 Pro running iOS 27.2. The installed dylib UUID matches the
  build output. The app launched successfully with the existing app identifier and data container.
- A physical-device XCTest passed and captured Hurry Up Tomorrow. The screenshot confirms
  beta's album header and artist facepile, hidden redundant artist lines, and explicit
  badges inline beside the track titles.
- The broader physical-device checks below describe the original branch. Co-artist handling,
  discovery layout and background reuse passed the current simulator checks. The broader device
  scenarios were not rerun on the phone during this beta installation check.

## Original-branch verification, 2026-09-24

- Full arm64 Theos package build passed, including the import-layer check.
- Simulator checks: 172 redesign, 146 native, and 172 with late header content. These exercise
  the production Logos hooks and policy, including reuse, larger multiline text, RTL, page isolation,
  metadata arriving late, co-artists, guest credits, label-backed badges beside clipped subtitle containers,
  long titles, badge restoration, same-size cached-row reuse, footer self-sizing and accessibility visibility.
  Paint checks cover nested album cards, artwork/badge preservation, page isolation, non-base colors,
  and plain UIKit playlist recommendation cells on initial layout and repeated reloads, including
  footer cells mounted outside the collection view data source.
- The inherited immersive-lyrics state tests passed.
- Installed the signed build on the connected iPhone 17 Pro. XCTest captured six positions on
  Hurry Up Tomorrow: repeated artist lines are hidden and explicit badges remain visible;
  More by, Related Music Videos and You might also like all appear below the tracks.
- Tapping the restored After Hours card opened its album and track list. The UI test waits for
  scrolling to settle before tapping the artwork, then waits for the destination track list.
- The Cry For Me context menu opened successfully from its original 48pt button.
- The device accessibility tree still reports complete track/artist names and explicit status,
  56pt track rows and 48pt context-menu buttons.
- Follow-up device validation: explicit badges sit inline on Hurry Up Tomorrow; repeated
  `Shae, Lava Dome` credits disappear on בונדהיזם. Both remain correct after scrolling away
  and back. Cached rows require `setNeedsLayout` after `prepareForReuse` even at the same size.
- The real badge is the label-backed `Components.UI.ExplicitIcon` sibling of the subtitle.
  The fixture now models that structure; the subtitle wrapper stays concealed when Encore
  refreshes its internal label. The shipped build contains no temporary tree/trace instrumentation.
- Background follow-up: verified transparent discovery-card captions on My Beautiful Dark Twisted
  Fantasy and the recommendation heading on This Is Drake, before and after scrolling away and back.
  The live hierarchy confirmed that Spotify mounts the playlist's plain footer cell directly in the
  list without including it in `visibleCells`; cleanup now includes those mounted cells.

The simulator exercises edge cases that the sampled album does not contain. This is a focused
album-page check, not a new acceptance run for the inherited Sing audio engine.

Reproduce the simulator checks with `THEOS=/path/to/theos python3 harness/album/test.py SIMULATOR_UDID`.
Original device screenshots remain in the original workspace's `out/album-118-119/`; the source branch contains
no Spotify binary, model, provisioning data or personal screenshots.
