# Music Haptics device validation — 2026-10-03

Issue: #108. Base: upstream `beta`, `49e02e2`. Device: iPhone 17 Pro, iOS 27.2,
Spotify 9.1.78. The physical test app also retains the owner's unrelated player artwork/lyrics
commit `a2d0134`; those changes are not part of this patch.

## Result

Native Music Haptics was physically confirmed in Spotify, on the Home Screen and while locked.
Control Center pause/resume worked, and publishing one verified catalog identifier corrected the
Dynamic Island warning. Several recordings were exercised, not just the initial Runaway reference.
The generated engine was excluded during native playback.

The final three-mode dropdown build was signature-verified, installed and launched normally
(installation database sequence 4720). A fresh preference read confirmed Native iOS remained selected.
The dropdown, info popup and mode transitions were inspected in the simulator; the installation and
launch are separate evidence from a tactile check of each mode on that final build.

## Recording identity and status

- Spotify's TRACK_V4 response supplies the recording's ISRC; both provider and entity status headers
  use HTTP-style 200. Now Playing's Spotify URI can include a playback UUID fragment, which must not
  prevent matching the recording.
- ISRC-only native availability returned false for Runaway (`USUM71027402`) even though Apple's
  catalog returned the same ISRC with `hasHaptics: true`. Supplying its exact Apple catalog ID caused
  AccessibilityUIServer to report availability and download the corresponding AHAP.
- The general lookup requires the same ISRC, a duration difference below two seconds and an available
  haptic track. There is no title-only matching or production hard-coded song ID.
- Publishing both identifiers allowed playback but left an unavailable warning. Publishing only the
  verified catalog ID corrected it. MediaRemoteUI then queried ID `1578323487` with `treatAsAdamID: 1`,
  received `available: true` and resolved Music Haptics status 0. The owner confirmed the warning was
  gone and vibrations still worked.
- Other native playback captures included Lights Burn Dimmer (`GBAHS2501741`, ID `1884102766`),
  a recording with ISRC `IL1042602304` / ID `6763939628`, and ID `1784157552` after a normal relaunch.
- On the tested OS, `isActive` stayed true while the Accessibility enable switch was off. The optional
  read-only `musicHapticsEnabled` selector reflected that switch. The selector, separate enable
  notification and catalog-ID export were checked against device symbols. No system preference
  setter or SpringBoard hook is used.

## Regression coverage

- 193 data checks: Spotify URI and ISRC validation; malformed/truncated protobuf and JSON replies;
  provider/entity errors; exact catalog matching; playback UUIDs; one published recording identifier;
  stale ID removal on mode/track changes; preserving artwork, lyrics and playback timing.
- Ten generated audio simulator scenarios, including native-mode exclusion and returning to
  generated output. The exclusion test failed before the listening-state guard was fixed.
- Six dropdown checks across native-available/unavailable scenarios: selecting None, Native iOS and
  spoti.pw Generated updates the existing preferences and shows only that mode's rows. A disabled
  native action cannot change preferences. Both old flags being on correctly displays Native iOS.
- The actual native popup and full info explanation were visually checked. The page harness uses
  UIScene with the current SDK.
- The shared Apple artwork harness passes after exposing its existing public web-player token helper
  for the catalog lookup. Layer and whitespace checks pass; the production arm64 tweak packages.

## Diagnostic findings and remaining limits

Earlier diagnostic success was not accepted: one temporary test set the native preference after the
generated engine had initialized. A later clean build failed physically despite active callbacks. The
production engine now checks native selection whenever listening is updated, and callbacks alone
are not treated as tactile proof or allowed to override a negative availability result.

A separate system failure reported that AccessibilityUIServer had exceeded its maximum haptic player
count (Core Haptics error 4097). Toggling Accessibility Music Haptics did not clear it; a phone restart
did. Native playback and the warning correction were confirmed after that restart, with no recurrence
in the final short captures. This patch does not establish a fix for system player exhaustion or
long-term engine stability.

Native mode needs catalog coverage and network access for uncached lookups. The optional catalog-ID
key and read-only enable selector are private compatibility details verified on this test OS; absent
symbols retain the public API path. The catalog lookup reuses the existing Apple web-player token and
queries the US catalog, so regional coverage can differ. Older supported iOS versions were not
physically tested. Podcasts, local files and unmatched recordings do not receive a catalog ID.

Generated haptics remain foreground-only: the owner felt no background vibrations even when temporary
instrumentation showed accepted Core Haptics calls. The production foreground gate is retained.
