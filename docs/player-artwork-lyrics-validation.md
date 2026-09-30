# Player artwork and lyrics polish

Based on `upstream/beta` at `49e02e2` (Spotify 9.1.78). All runtime changes are in the redesigned player.

## Behavior

- Animated artwork dissolves into a subdued color sampled from the clip's lower edge. The fade ends at the song details, leaving the lower controls over color.
- Opening lyrics crossfades to the existing Fluid artwork background. The video stays paused and ready to return when lyrics close.
- After four seconds of playing lyrics, only the lower controls disappear. The header, artwork thumbnail, song title and artist remain visible, with lyrics below them.
- Scrolling keeps the controls hidden. A tap restores them without seeking. The thumbnail can close lyrics in either state.

## Automated validation

- Theos device package builds successfully; the signed app passes deep, strict signature verification.
- Layer checks and `git diff --check` pass.
- Player harness, iOS 27 simulator: `animated` **21/21**, including pause/resume, missing/downloading clips, Spotify video, lyrics background, retained video, new tracks during lyrics, and interrupted transitions.
- Player harness, Spotify Free units on iOS 27 simulator: `taps` **29/29**, including seeking, scrubbing, song details staying visible, immersive scrolling, a restoring tap that does not seek, and the thumbnail closing lyrics.
- The harness now uses the scene lifecycle required by the installed iOS 27 simulator. The final thumbnail checks are chained so a later step cannot reopen lyrics before the preceding assertion runs.

## Device verification

The combined build was installed and launched on an iPhone 17 Pro running iOS 27 with Spotify 9.1.78, preserving the existing app identifier and data.

Screenshots confirm the subdued footer on an animated Canvas and the return to the blurred artwork field when lyrics open. Physical-device verification of immersive scrolling on a song with lyrics remains pending; the 50 simulator assertions above passed.

## Recheck

In Redesigned UI on iOS 26 or newer, open a song with animated artwork and lyrics. Check the lower fade, open lyrics, play for four seconds, scroll, and tap. The blurred background and song details should stay visible; scrolling should keep lower controls hidden, and tapping should restore them. Tap the thumbnail to return to animated artwork.
