# Working on the mod

## Layout

    tweak/                      the Theos project: Makefile, control, the bundle filter plist
    tweak/Sources/Core/         what every file builds on: logging, preferences, view-tree walking, glass panes, the
                                look this launch runs (SGUIMode.h), the forced-flag registry (SGFlagForce.h) and C
                                functions Spotify imports hooked by rebinding its import slots (SGRebind.h)
    tweak/Sources/Headers/      reverse-engineered Spotify classes, one header each, only the selectors used
    tweak/Sources/Settings/     the Mod Settings framework: SGPage (a page on Spotify's stack), SGModPage (sections
                                of rows: switches, choices, sliders, links, and rows shown only while a switch
                                is on), SGPageStyle (Spotify's list look), SGGlowSwitch
    tweak/Sources/Shared/       what works the same with either look, see Layers below
    tweak/Sources/Native/       tweaks on Spotify's own screens, running only while Redesigned UI is off
    tweak/Sources/Redesigned/   the redesign, running only while Redesigned UI is on
    tweak/Sources/App/          what brings the layers together: Mod Settings' root and composed pages, the Mod page,
                                backup and signing, the welcome tour
    tweak/Sources/Diagnostics/  screen dumps, the tree server and the main thread hang sampler of FLEX builds
    extension/LiveActivity/     the Live Activity widget, a WidgetKit extension of its own
    extension/AppGroups/        a dylib loaded by Spotify and its home screen widget that moves Spotify's App Groups
                                into a group the re-signed IPA has; without it the widget stays a placeholder. Keychain.m, in the
                                same dylib (so in Spotify and each Siri and widget extension), answers the SecItem calls that name
                                Spotify's <team>.com.spotify.client.extension-credentials group from a property list in that App
                                Group's container, through dyld's __interpose, since the re-signed app and its Siri extension are
                                not entitled to that keychain group and the extension could not read the login token the app keeps
                                there (Siri answered "verify your account details"); every other call goes to the real keychain, and
                                a process entitled to the group for real is left alone
    scripts/                    pipeline.sh (build + inject), build-extension.sh (the widget extension, without an
                                Xcode project), merge-appintents.py (the widget's intents into Spotify's), insert-dylib.py (a load command into
                                Spotify's widget), install.sh (sign + install), record-trees.py, record-session.py,
                                dump-log.sh, extract-flags.py
    trees/                      recorded view trees, one per screen; the input for every new hook. trees/clean/ holds
                                the numbered snapshots per screen of record-session.py, taken of Spotify as it came
    plist/                      Info.plist overrides merged into the app (turns UIDesignRequiresCompatibility off)
    vendor/                     AutoFLEX deb; audio/, the third-party C of the audio effects (libbs2b, WDL's EEL2) and
                                the EEL2 parser of the mod's own, built by its own Makefile into a static library the
                                tweak links (its README names the upstream commits and the licenses)
    ipa/, out/                  decrypted Spotify IPA in, built IPAs out (both gitignored)

`tweak/Sources/Shared/Flags/SGFlagList.m` is generated from the IPA and gitignored, as are the
recorded trees: both are read out of Spotify's own binary and belong to whoever built them.

## Layers

The mod has two looks, picked by Redesigned UI in Appearance: Spotify's own screens with the mod's
tweaks on them, or the redesign, which starts from a clean sheet. What does not draw on Spotify's
screens works under both. So the sources are four layers, each a directory of features:

    Shared/       works the same with either look
    Native/       Spotify's own screens tweaked; every %ctor starts with `if (!SGNativeUI()) return;`
    Redesigned/   the redesign; every %ctor starts with `if (!SGRedesignedUI()) return;`
    App/          Mod Settings' root and the pages that combine the layers, the Mod page, the tour
                  (About/WhatsNew.m: the first launch after an update lists the version's release notes, read off
                  the releases Update.m keeps, and the Mod page's What's new opens it again)

`SGRedesignTested()` (Core/SGUIMode.h) is YES from iOS 26: the redesign is Liquid Glass, and
`UIGlassEffect` is the system's, so on an older OS the glass calls fall back to a blur and the redesign
runs untested against an older UIKit (issue #37, an iOS 17 scene-update watchdog). Below 26 it can still
be picked: App/Pages.m's restart alert and the tour's note under the cards say it is untested first, and
`SGSetRedesignedUI()` stores `SGKeyRedesignUntested` along with the switch. Without that key the redesign
does not run below 26, and `SGRedesignedUI()` turns off a switch stored before the warning existed.

The two looks never run together, so each hooks the same Spotify class in its own way, and a part of
the look is edited on its own side without touching the other: where both need the same thing, each
has its own copy (the tab bar's composition and its editor, the lyrics page's glass, the soft top edge,
AMOLED, the accent colour), under its own names (SG… native, SGR… redesign) and its own keys. The imports run
one way, Core <- Settings <- Shared <- Native | Redesigned <- App, and `scripts/check-layers.sh`, run
by tweak/Makefile before every build, fails on any other. A layer below that needs something from one
above takes it through a registry in Core (forced flags, SGFlagForce.h) or a function declared low and
defined high (SGOpenModSettings).

A feature is a directory in its layer holding everything about one area of the app:

    <Feature>.h            the keys of its switches, and the functions other files may call
    <Something>.x          the hooks, one file per screen or mechanism, each ending in its own %ctor
    <Feature>Settings.m    its Mod Settings page, or its sections for the page of the part it changes, built from
                           the rows in Settings/SGModPage.h; App/Pages.m puts them on the page
    <Model>.m              plain Objective-C the hooks and the page share, where there is any

Shared:

    Privacy/      telemetry blocking and its counters, and the Search switches that force their flags off (Clutter.m)
    ArtistBlock/  tracks by blocked artists skipped as they start (ArtistSkip.x), the list and the Blocked artists page under Player
    Flags/        Spotify's remote-config flags: the provider hook, the generated table, the All flags page and the Labs page
    Gestures/     the double tap zones on the player: the grid, what each cell does, the recognizer (each look hooks it on)
                  and Hold to play faster (Player page): a long press on the left or right third plays at 2x until it lifts
    Lyrics/       the lyrics engine for the redesign's Apple Music style lyrics and the lock screen: lines read from
                  color-lyrics and the player's clock (KaraokeSource.x), words timed by estimate inside Spotify's line
                  times (KaraokeTiming.m), which line to name where two voices sing at once (the one that came in first,
                  for the lock screen and the Live Activity), and the Lyrics page's parts; every song's lines, once
                  they load, are saved on the phone (LyricsOffline.m, Lyrics > Save lyrics offline, on until switched
                  off, at most 20000 songs, the least read going first) and read back before any source is asked, so
                  they show at once and without a connection. Lyrics > Download all lyrics (LyricsDownload.m) saves a
                  whole library's at once without playing it: Liked Songs, and the library's playlists if asked, listed
                  from the Web API with the app's own sign-in, each song not saved yet named for the sources
                  (SGLyricsNameTrack) and asked as a song that plays is, one at a time, paused while the app is away
    LyricsSources/ the sources lyrics come from, asked in the order the Lyrics page puts them in and merged into the
                  best answer (LyricsSources.m, the list to drag in LyricsSourcesPage.m): Apple Music's TTML from
                  BiniLyrics.m and Unison.m, read by SGTTML.m, which carries a second voice and the
                  backing vocals, and in its head Apple's translation and its pronunciation of a line, the pronunciation
                  timed word by word (the translation taken in the Lyrics page's language); SpicyLyrics.m, the Spicy
                  Lyrics developer platform's GET /v1/lyrics/{id}, matched by Spotify's track id and asked with a
                  publishable key of the user's own (see Spicy Lyrics below), carrying syllables, backing vocals, a
                  duet's sides and the credit its terms require; Musixmatch.m, matched by
                  Spotify's track id with an anonymous token, word timed where it has richsync; NetEase.m, word timing from yrc for what the others only line time; LrcLib.m, open and
                  keyless and timed by the line, the floor under the rest. color-lyrics is answered with whichever won
                  (LyricsHook.x): Spotify's own 200 gets our lines swapped in; a track Spotify's metadata says has none has
                  its request sent to a donor track that does, so the reply is a real 200 (a 404 answered as a 200 in the
                  delegate alone never showed the card on 9.1.78); a 404 for a track not seen yet is held until the chain
                  answers. The card list the server sends per track (scrollsita) carries a lyrics section only for tracks
                  Spotify has lyrics for, so one is added to any list without it: that is what makes the player ask for the
                  lyrics and show the card. has_lyrics is forced on for every track, the walk starts at the track change
                  for it and the next, and the player's card-loading timeout flag is forced to its 5 s maximum while a
                  source is on. None of it runs while EeveeSpotify is injected with its own lyrics on (SGLyricsActive()):
                  its hook on the same delegate calls blocks on a lyrics fetch, and LyricsHook calls it from the main
                  queue. The Lyrics page says so
    LyricsTranslate/ Gemini translation (Lyrics page, redesign): lyrics kept without a translation for most lines go to
                  Gemini (gemini-flash-latest, the user's own key under spotipw.gemini.key, outside the prefix like
                  Spicy Lyrics') as one numbered list in the translation language, or the iPhone's for Any, and come
                  back as a JSON array of the same length, set on the lines and kept again so the views redraw; a
                  wrong length is dropped, answers are cached for the session, a refusal waits ten minutes
    LyricsSources/LocalLyrics.m: a local file (spotify:local:) is named "local~" and an FNV-1a hash of its URI in
                  the lyrics engine (SGKaraokeLocalTrackID), never sent to Spotify or the sources asked by
                  Spotify's id; its lyrics are what was typed in for it (Documents/spoti.pw/Local lyrics/<id>.lrc,
                  LRC or plain lines, from the Lyrics page's "Lyrics of this local file" sheet while one plays),
                  else LRCLIB's by the title, artist and length its URI carries
    LockScreenLyrics/ the line being sung in the system's now playing, checked ten times a second; and the lock
                  screen visualizer (Lyrics > Lock screen visualizer, read at launch): while Spotify is not on
                  screen and the sound moves, a timer at 6, 10 or 15 a second reads the visualizer's bars, draws a
                  frame off the main thread (Visualizer/SGVisualizerFrame.m: the cover as a circle in the ring over
                  it blurred, the line under it when lock screen lyrics show the line as the artwork) and sends the
                  info again with that frame as the artwork; the cover is fetched from Spotify's artwork on that
                  queue, never the main thread. An animated artwork (LockScreenArtwork/) is drawn over it, so the
                  Canvas is best off with it. The CarPlay visualizer (Visualizer > CarPlay, read at launch) runs the
                  same frames while CarPlay is connected (the route's CarAudio port, or a CarPlay scene up), Spotify
                  on screen or not: CarPlay's Now Playing shows the now playing artwork, the only picture an audio
                  app can put on the car's screen
    LockScreenArtwork/ the track's Canvas or its album's Apple Music cover as the lock screen's animated
                  artwork, from iOS 26 (Apple takes an MPMediaItemAnimatedArtwork under one of
                  MPNowPlayingInfoCenter's animated artwork keys, and the mod puts one there through a second
                  hook on setNowPlayingInfo:, so the lock screen lyrics' rewrites of the same dictionary carry
                  it). The sources are asked in the user's order (Spotify, then Apple Music until set, on the
                  shared Settings/SGOrderPage the lyrics sources use too). Spotify's URL comes off canvas.url
                  in the played track's metadata, which Spotify's core fills whatever
                  ios-feature-canvas.canvas_enabled says, and failing that from spotify.canvaz.cache with the
                  account's own token. Apple Music's (SGAppleArtwork.m) comes from the catalog search with
                  editorialVideo extended, under the web player's token read from music.apple.com's script and
                  kept until it expires; the HLS stream near 1100 px wide, HEVC first, is byte ranges of one
                  MP4, which is fetched whole. The clip is downloaded into Caches, centre cropped once to the
                  shape the key wants (Apple's 3:4 cover needs none) and kept under a 120 MB cap. The
                  redesigned player's Animated artwork asks the same sources (SGArtworkAsk) in an order of its
                  own; a search or a download both ask for at once is made once and answers both. Checked on
                  the Mac against harness/lockart/
    Navigation/   the page transition fix (PageTransition.x) and opening a spotify: link (Links.x)
    ConnectDiscovery/  Bonjour resolves local Spotify Connect receivers. When Spotify's own mDNS send
                  fails without the multicast entitlement, a bounded round sends its query by IPv4/IPv6
                  unicast to all resolved receivers and replays validated replies to Spotify's socket.
                  A short wait also catches receivers still resolving. Connected sockets are left alone.
                  The IPA declares Connect and Google Cast Bonjour service types; pipeline.sh keeps the
                  IPA's existing types. This bridge handles Connect only; Cast is Bonjour-declared but
                  has no equivalent packet bridge here.
    Audio/        the mixer connection and RemoteIO render notify owned once (SGAudioPipeline.x): fixed processor slots
                  run speed and pitch, audio effects, then music haptics. Spotify keeps an output chain per sample rate
                  (a local file at another rate gets its own), so each RemoteIO pulls only its own mixer and the
                  processors follow the one connected or started last. Graph changes and disposal exclude active pulls;
                  the render thread never waits for them. Unsupported formats retain Spotify's connection. The PCM
                  packet queue is bounded and generation-stamped. Sing's source read-ahead reads guarded queue metadata
                  for the verified Spotify binary; PCM still comes through its AudioUnit. Boundary tests are in harness/audio/ and harness/sing/
    Sing/         the local Core ML separator, source-domain audio adapter, worker and player lifecycle, from iOS 18. Core ML
                  uses the GPU in the foreground and its warm CPU model in the background. The audible
                  clock follows emitted source samples while delayed audio drains. Model loading overlaps source capture;
                  verified continuous next-track PCM keeps its worker and reserve across a natural transition.
                  Redesigned/Lyrics owns the Now Playing microphone control and Mod Settings' Karaoke page. The voice
                  model (about 470 MB) is not in the IPA: SGSingModel.m downloads its files from the model host in a
                  background URL session, checks each against a size and a SHA-256 pinned in the code, and moves
                  them into Application Support/spoti.pw/Sing only when all are right (SingModel.x reconnects at
                  launch). Tested against harness/sing/ (the download against a local server, model_test.py)
                  Spatial voice (SGSpatialVoice.m, its switch on the Karaoke page): with head tracking AirPods the
                  separated vocals are panned against the head's turn in SGSingDSP's mixer -- constant power, the far
                  ear up to 0.66 ms later and shadowed -- so the voice stays in front while the instrumental stays
                  as mixed; Follow iPhone lets front settle where the head rests over eight seconds. It ramps in
                  and out with the level, so a bypass still lands on the untouched original (harness/sing/dsp_test.c)
    Fonts/        one font for the whole app (Appearance > Font, read at launch): UIFont's system constructors,
                  preferredFontForTextStyle:, fontWithName:size: and fontWithDescriptor:size: hand back the picked
                  family (or SF's Rounded, Serif or Mono design) at the same size and nearest weight, for the
                  system's faces and Spotify's SpotifyMix and Circular ones only, so icon fonts are left alone;
                  the new font is made with the hooks stood down by a per-thread flag, and cached
    Visualizer/   a ring of bars moving with the music, NCS style: the finished sound off Audio/SGAudioPipeline's last
                  stage (SGAudioStageVisualizer, VisualizerTap.x, which joins the pipeline only when a ring first
                  shows, never at launch: registered there it froze Spotify as a song started) into a single writer
                  ring, only while a ring is on screen, and rings drawn in the same frame share one analysis; once a frame the newest 2048 samples go through a Hann window and an FFT into log spaced
                  bands against the loudest lately (SGSpectrum.m, plain C, harness/visualizer/; the newest 1024
                  samples, 2048 for Bass and for more than 256 bars, with a quick rise and fall, so the bars are on the
                  beat; 48 to 1024 bars, from 128 up read between the bins and smoothed into their neighbours, so 1024
                  is a smooth circle; a fifth of the ring, or Even, a quarter or a third, for 20 to 100 Hz and the rest
                  from 100 Hz up, read between bins on the longer window, which Bass, all bass already, ignores; bars
                  that rise and fall snappily, normally or smoothly), following
                  everything, the beat or the bass at a strength, as Music Haptics does or with Music Haptics' own
                  settings; SGVisualizerView draws them as bars, a wave or dots, thin, normal or thick, short, medium or
                  full height, with falling peak caps and a slow or fast turn of the whole ring if asked, in the accent,
                  white, every hue or the Cover gradient (SGCoverPalette.m: five colours of the cover, read off the cover
                  the ring on screen shows (never the hidden rings round the songs either side), or the now playing
                  artwork where nothing shows one, off the main thread; SGPalette.m, plain C, reads them one of two ways
                  the Cover colours row picks: Spots blurs the picture and reads it at its centre and the middle of
                  each quarter, so only colours that cover a good part of it come back, and Main colours is k-means
                  in OKLab weighted by how vivid each pixel is, black left out; either way lightened to show on black,
                  unless the Dark colours switch keeps them as dark as they are, black included, tested in
                  harness/visualizer/palette_test.c; the Backlight switch lays a soft radial glow under the bars,
                  white behind dark ones and black behind light ones by their mean luminance, in the player's ring,
                  the lock screen's frame and the Live Activity's ring alike), a gradient colour laid along
                  every bar from its darkest colour inside to its lightest at the tip (a radial gradient the bars mask),
                  once round the ring, there and back four times, or bar by bar (a shape layer a colour), fading to the
                  next track's on a display link run the lyrics'
                  way (60 to 120 Hz, down during player transitions and off screen). The redesigned player rings
                  its cover with one (PlayerArtwork.x; Mod Settings > Player > Visualizer, a page of its own under either look,
                  VisualizerSettings.m, Sound, Shape, Colour and Lock screen): the cover a circle at 64 % with a
                  round shadow, the ring behind it in the tilt view fading with it, and the picture inside slowly
                  turning while the song plays
    HeadMotion/   AirPods head tracking, one CMHeadphoneMotionManager the features share, running only while one asks
                  (SGHeadMotion.h); NSMotionUsageDescription is added to the IPA by merge-local-network-plist.py
    HeadGestures/ AirPods gestures (Mod Settings > AirPods gestures): a double nod or a shake of the head runs the
                  player command picked for it (play or pause, next, previous, start over), skips only while something
                  plays; SGHeadGestureDetector.m, plain C, tells a deliberate gesture -- three or more quick swings on
                  one axis, begun and ended in stillness -- from nodding along, which never rests. Tested on the Mac or
                  Linux against harness/headgestures/
    ListeningStats/ Listening stats (Mod Settings > Listening stats): every listen of a track logged from the player's
                  state (SGListeningLog.m, Application Support/spoti.pw/Stats/listening.json, written every 30 s and
                  when Spotify leaves the screen), a play from 30 s on; the page sums the last four weeks, six months
                  or all time into minutes, plays, top tracks and top artists, each opening in Spotify. Local only
    Player/       the player's open and close announced (PlayerEvents.x), what the player is doing read through
                  one hook for every feature that wants it (PlayerState.x), the lock screen widget's flags, and in the
                  more button's menu Speed and pitch: both done to Spotify's audio by Apple's time and pitch unit, put
                  between its mixer and its RemoteIO unit through Audio/SGAudioPipeline's connection
                  (SpeedPitchMenu.x, SpeedPitch.x, SGTimePitch.m). With Pitch follows speed on (the default, stored) the pitch
                  slider folds away and Apple's varispeed takes the unit's place: the song resampled like a record, no
                  time stretch to smear it. The block goes into Spotify's own context menu sheet
                  and is drawn from its own measures, not the Kit's, so it sits there under either look. Tested on the
                  Mac against harness/pitch/ and in the simulator against harness/speed/ and harness/menu/.
                  Presets (SpeedPitchPresets.m, Mod Settings > Player > Speed and pitch presets, SpeedPitchPresetsPage.m,
                  and a Preset line first in the panel): a name for a speed, a pitch and whether pitch follows speed, up to 50,
                  stored as property lists under spotifyglass.speedPitch.presets. SGPlayerApplySpeedPitch sets all three at
                  once and keeps them until Spotify's output has started when they come in before a song plays. Siri and
                  Shortcuts are App Intents (SpeedPitchIntents.swift: the preset as an App Entity with a string query,
                  Use speed and pitch preset, Set speed and pitch, Reset speed and pitch, and App Shortcuts with the phrases
                  "Use <preset> in <app>" and so on): scripts/build-extension.sh hands the file to the App Intents
                  metadata processor as the module the tweak compiles in, and scripts/merge-appintents.py adds its
                  actions, entity, query and App Shortcuts to Spotify's own Metadata.appintents (the shortcuts are left out
                  if Spotify's file already has some). The intent runs in Spotify's process, in the background when it is
                  not open, and posts a notification the tweak acts on (SpeedPitchIntents.x, observers put up as the
                  tweak loads); Siri is told the presets again, through SGSpeedPitchShortcutsBridge, when they change
    AudioEffects/ the audio effects on Spotify's sound (AudioEffects.h has the keys and the page's calls): Audio/SGAudioPipeline's
                  ordered output processor runs each finished buffer through the mod's own engine, re-blocked to 1024 frames one block late,
                  in place (AudioEffects.x, SGDSPEngine.m). The buffers are in the unit's output format, the
                  hardware's, not the client format Spotify sets. The effects are the SGDSP*.m files, on Accelerate,
                  Apple's Reverb2 unit, libbs2b and EEL2 (vendor/audio). Settings apply as they change, on a queue of
                  its own; the file effects read their files from Documents/spoti.pw/Audio effects
                  (AudioEffectsFiles.m). Tested on the Mac against harness/audio-effects/, the hook in the simulator
                  against its sim/
    Haptics/      Vibrations (Haptics.h lists its files): a tap of UIKit's feedback generators for the player's and the now
                  playing bar's controls, the scrubber's tenths and ends, cover swipes, gestures and the lyrics page's tap to
                  seek, at the strength set for them (ControlHaptics.x, SGFeedback.m); and Music Haptics, Core Haptics
                  playing along with the song: Audio/SGAudioPipeline supplies final samples after speed, pitch and audio effects;
                  in the unit's output format (the hardware's), they go through a drum
                  and bass analyzer on the render thread (SGMusicAnalyzer.m, plain C), and a thread of its own schedules
                  the taps and the rumble for when the sound is heard, at their strength and leaving out what Follows
                  leaves out (MusicHaptics.x). Everything applies at once; nothing plays while Spotify is not the active
                  app. The analyzer is scored on the Mac against harness/haptics/, the hook in the simulator against its
                  sim/, the settings against harness/haptics-page/
                  iOS Music Haptics (SystemMusicHaptics.x, iOS 18, on until switched off, read at launch): the IPA
                  declares MusicHapticsSupported, each track's ISRC is asked of Spotify's Web API with the app's own
                  token and added to the now playing info, so iOS plays its own haptic track in the background and
                  on the lock screen; while MAMusicHapticsManager says it has one for the song, the mod's steps aside.
                  The lookup is tried again while the song plays when Spotify's token is not there yet or it fails, and
                  the Vibrations page's Now row says what iOS's is doing for the song. iOS plays no haptics of an app's
                  own in the background, so out of the app iOS's is the only one there is
    LiveActivity/ a Live Activity on the lock screen and in the Dynamic Island in one of four views, the line being
                  sung with the next one under it, the tracks up next (a tap on one skipping ahead to it), the player (the
                  cover in a ring of the visualizer's bars, mirrored, each bar in the cover's colours from the inside out,
                  read once, twice or four times a second while Spotify is not in front and the song plays and sent as a
                  hex digit a band, the widget gliding them to their new lengths; the cover a file in the app's first App
                  Group, read by the widget when it may open the group, and a 40 px picture in the state otherwise, left
                  out when the state would pass ActivityKit's 4 KB; previous, play and pause, next and like; a bar with the
                  time in and left, cut into 24 buttons that seek to where they are, which iOS's own controls cannot be
                  replaced by but sit beside), or a control
                  menu of tabs, Controls (previous, play and pause, next, shuffle, repeat), Queue and a sleep Timer of
                  the mod's own that pauses Spotify (LiveActivity.h lists its files): a timer polls the player and
                  sends a new state only when what the view shows changes, local updates only, no push. Taps are
                  LiveActivityIntents run inside Spotify and take a second or two to show on the card. The widget is extension/LiveActivity; ActivityKit pairs the two
                  by the attributes' type in LiveActivityShared.swift, compiled into both. It starts only with Spotify
                  in front; its switch and its view apply at once

Native:

    Appearance/   AMOLED (Amoled.x), the accent colour (Accent.x), the soft top edge (EdgeEffect.x), and Repaint.x, which
                  keeps what the native tweaks stripped transparent
    Navbar/       Spotify's tab bar composed (Navbar.x, NavbarLayout.m, hooked from TabBarHooks.x), the Navbar and Add a tab pages
    NowPlayingBar/ the device button hidden, the bar's flags
    Player/       the full screen player (Player.x), its cards and buttons hidden (PlayerDeclutter.x), the glass lyrics card
                  (LyricsCard.x), the gestures' hookup, the Queue & devices flags
    Lyrics/       the full screen lyrics page on glass (LyricsPage.x)
    Home/         the Home gradient, Home's sections and pills hidden (HomeDeclutter.x), the Home & Library page
    Playlist/     the playlist header and pills, hidden one switch each
    Album/, Artist/ their pages' parts hidden, and the cover or photo behind their headers

Redesigned:

    Kit/          what the redesign builds on (SGRKit.h lists it), the flags it forces (SGRedesign.h, SGRGlassDesign.x for
                  Spotify's own glass design), its repaint hook (SGRRepaint.x), soft top edge, AMOLED black (always on,
                  SGRAmoled.x) and its own accent colour (SGRAccent.x, stored apart from the native look's); and
                  the curtain the playlist, album and artist pages come in behind (SGRReveal.h): black over the
                  whole page from its first pass until the picture, the field's colour, the header with Play and
                  the first track with its text are all in, and then the page fades in from behind it in one
                  go -- the field brightening into the page's colour, the rest fading in where it is, nothing
                  moving -- so it no longer arrives a piece at a time; after 1.2 s it shows whatever is missing, and
                  the back button, being the system's navigation bar, is there throughout
    Navbar/       the glass tab bar (TabBar.x) over its own composition (Navbar.x, NavbarLayout.m) and editor, with the fade to
                  black over the pages behind the bars that Spotify's bar drew; the glass search field.
                  Spotify is made to leave the glass bar its height where its own bar is shorter (a phone with a home button,
                  Offline or Private Session under the bar), so the now playing bar and the pages move up with it. Laid out on
                  the Mac against harness/tabbar/
    NowPlayingBar/ the glass now playing bar (NowPlayingBar.x), with Spotify's device button on it hidden on request
                  (BarConnect.x, its own key and its own row on the Player page, apart from the native look's)
    Player/       the redesigned full screen player (Player.h lists its files), on Spotify Free's units too (a Free
                  account with pick and shuffle gets NowPlayingReinventFreeMode, whose units are classes of their own
                  around the same elements, and each unit hook covers both); its ⋯ opens Spotify's own sheet, sliding up
                  from the bottom with every row Spotify has and Speed and pitch's block in it (Shared/Player), unless
                  Music app style menu is on (Player page, off until switched on, read at launch), when it opens a menu the way the
                  Music app draws one (PlayerMenu.x, SGRPlayerMenu.m): a pane of glass grown out of the button,
                  Add to playlist, Add to Queue and Share as three tiles across its top, groups of rows under
                  them, Speed and pitch opening onto Shared/Player's sliders in place, everything else Spotify
                  offers under More, and Remove from this playlist last in red. What is in it and what each row
                  does stay Spotify's: its own sheet still opens, out of sight, and the menu is read off its
                  table, each row placed by the number Spotify's ListRow carries as its identifier and fired
                  through that ListRow; a page Spotify pushes onto the sheet (Share's destinations) shows the
                  sheet, and a sheet with no rows within 4 s is shown as it is. It opens on the rows the last
                  menu had, kept across launches, and moves to Spotify's as they come in, a tap meanwhile held
                  until they do. Tested in the simulator against harness/playermenu/
                  With Sing on (it stops when the iPhone runs hot, unless Karaoke > Ignore temperature, SGKeySingIgnoreHeat, is on), on the built-in separator or the downloaded voice model (Mod Settings > Karaoke, Redesigned/Lyrics/SingSettings.m,
                  both applying at once), its microphone (Redesigned/Lyrics/SGRSingControl.m) sits in the
                  lyrics' bottom trailing corner, opposite their glass button, and goes down with the lines when the
                  controls go; while it is open, preparing or explaining itself the controls stay, and a touch on it
                  does not bring them back. What Sing is doing shows on the button, not in words: a ring turning
                  round the microphone while it prepares or recovers, a white fill up to the vocal level while it is
                  on, glass when it is off and a dimmed microphone when it has stopped
    Lyrics/       the full screen lyrics page on glass with Apple Music style lyrics over it, always on (SGRKaraokeView,
                  which the player shows in itself too, Player/PlayerLyrics.x, where after four seconds untouched while
                  the song plays the controls fade out and the lines take the whole player, until a touch or a pause
                  brings the controls back; the tap that does so seeks nowhere): lines sung over each other lit together,
                  the stack moving on once the first is sung out; an instrumental break of 7 s or more held by three dots
                  that breathe and fill over its length on a Core Animation timeline laid against the song's clock; and
                  a line's pronunciation (under the words it spells) and translation, switched on from a glass button in
                  the lyrics' corner that shows only for a song that has them, in the order of sizes the Lyrics page sets
                  (LyricsText.h). Laid out on the Mac against harness/lyrics/
                  A sung word glows with how long it is held (a shadow on the word view, gone after it), and a word
                  held a second or more is a row of a label per letter that rises in a wave as the sweep passes
                  The lyrics look editor (LyricsLook.m, Lyrics > Lyrics look) scales the size and the gap between
                  lines, picks the weight, scales the blur (0 for none) and sets how bright an unlit line is; the
                  views read it as they lay a song out and restyle in place when it changes
                  Landscape lyrics (LandscapeLyrics.x, on until switched off, read at launch): the phone held on its
                  side for a third of a second while a lyrics view shows lines brings up a window of the mod's own
                  over Spotify's, which runs in portrait only, its content turned a quarter round, with a lyrics view
                  of its own (SGRKaraokeView.landscape, left out of lyricsOnScreen); upright again, or ✕, closes it.
                  A lyrics view also restyles when its song's lines are kept again with translations added
    Home/         Home decluttered to music on black (an allow list of its sections: shortcuts, the DJ without its heading and
                  transcript, the shelves of cards), a large title where the filter pills were with the avatar at the trailing
                  edge, the shelves' headings at the Music app's size, each shortcut tile's cover run across it blurred
                  (SGRPalette's extension), continuous corners on the covers, and in FLEX builds a meter of each scroll's
                  frames and the hooks' time (Home.h lists its files)
    Search/       the Browse page decluttered to its category cards (an allow list of the list's cells: the watch feed
                  carousels and promos collapse, and the cards move up by the spacing they leave), the header the way Home
                  has it without the camera, and each card as Liquid Glass tinted by its own colour, read off the Box's
                  shape layer (Search.h lists its files)
    Library/      Your Library the way Home and Search have their headers: a large title at the leading edge, the avatar
                  at the trailing edge with the search and create buttons before it, the header's scrim gone, each row's
                  artwork at the Kit's radius with a circular one left round, a hairline between the rows, and the search
                  inside the library on glass capsules (Library.h lists its files). The filter chips under the row stay
                  Spotify's: they were taken out when this was first built and put back in 0.21 (issue #20), since
                  sorting a library is not something the page can do without, and Spotify already draws them on the
                  system's own glass
    Playlist/     the playlist page (Liked Songs and one's own too, all three being the same page) the way the Music
                  app lays one out: the cover full bleed across the top dissolving into the page's field with no seam,
                  the title, the creator after their picture and the length centred under it, one row of glass
                  controls (shuffle, a prominent Play capsule taking its glyph and its word from Spotify's own button,
                  add), the find bar and the curation pills gone, and the track rows on the field with a hairline between them
                  (Playlist.h lists its files). Sort and Mix, the two of those pills the ⋯ menu does not already offer,
                  are put on that menu's own sheet instead, above Spotify's rows, and fire Spotify's own buttons.
                  Laid out on the Mac against harness/playlist/
    Album/        the album page laid out the same way, on the page the Creative Work Platform builds rather than the
                  playlist's, so it shares nothing with Playlist/ but the Kit: the cover full bleed dissolving into the
                  field, the title, the artist after their picture and the kind and date centred under it, and the
                  same row of glass controls -- play and shuffle float over the album page outside its header, so they
                  are concealed there and the row carries the Kit's stand-ins, which draw their glyph and fire them. Under the tracks
                  everything the server sends is dropped -- more by the artist, videos, concerts, merch, you might also
                  like, and whatever it adds next -- but the album's own line and its copyright (Album.h lists its
                  files). A podcast's episode page is the same template, so it is given the same field, and what it
                  paints over it is taken off. Laid out on the Mac against harness/album/

App:

    ModSettings.x  the root page and the rows that open it from Spotify's settings and the side drawer
    Pages.m        the Appearance card with Redesigned UI, the Player and Lyrics pages, which Navbar page opens
    About/         the update check against the repo's GitHub Releases, the Updates page it fills (the state, and
                   the changelog of every release newer than the build, a line per commit) and the sheet a newer
                   release brings up on its own a few seconds after Spotify opens, once per release; backup, the
                   signing warning and the Mod page with the reset; how the app is signed (Certificate.m: free,
                   paid, enterprise or no profile, sent with the usage ping), and for a free Apple ID a row with
                   the day it runs out and, at most monthly, a certificate sheet worded by spoti.pw/api/certificate
    Onboarding/    the welcome page over Home on the first launch, with Redesigned UI, offered again from the Mod page
    Sheet/         the card the Ko-fi ask and the certificate offer rise in, with its glowing button

Every key a feature stores starts with `spotifyglass.`, whatever it holds: Reset all settings on
the Mod page removes by that prefix and has no list to keep up to date. It leaves `SGKeyStock` behind,
which makes every unset switch read off, so a reset is stock Spotify whatever switches exist.

A hook reads its switch when it runs (`SGEnabled`, `SGHidden`, `SGFlag` from Core/SGPrefs.h), so a
change shows after Spotify restarts; the tab editor on the Navbar page is the exception and applies as soon as the bar lays
out again, as are the Home gradient's colour, strength and height, but not the switch that turns it on, and Vibrations
and Live Activity. The root page in `App/ModSettings.x` holds the Appearance card and links the page of each part of Spotify, and only the stored look's.

## Spicy Lyrics

Spicy Lyrics answers only a key, and its terms want every deployer to have their own, so each user
makes one (16 or older, free):

1. Sign up at developers.spicylyrics.org (email, password, the emailed code).
2. Dashboard, Applications: create an application. Ignore its secret key (`sl_sk_`), which must stay on
   a server.
3. Turn on client access for it and add **No origin header** to the allowed origins (it asks for a
   confirmation). Copy the publishable key, `sl_pk_…`.
4. Mod Settings, Lyrics, Sources: Spicy Lyrics key, paste, Save; tap Spicy Lyrics to put it in the order.

The key is stored under `spotipw.spicylyrics.key`, outside the `spotifyglass.` prefix, so no settings
backup, diagnostics dump or reset carries it; only an `sl_pk_` key is taken. A 401 or 403 is shown on
the Sources page ("Key rejected: …", from the error code) and the key is not asked with again for ten
minutes or until it changes; a 429 or 503 is waited out for its Retry-After (or RateLimit-Reset), and
the last request of a window waits out the rest of it. Answers are kept in memory per track only (the
terms allow 30 days). The credit is required: "Apple Music via Spicy Lyrics", "Spotify via Spicy
Lyrics", or for a community sync "Spicy Lyrics, uploaded by …, made by …" with both linked. The
redesign's lyrics show it whatever Show source says, a tap opening the links; the native look puts it
in Spotify's own "Lyrics provided by" line under the lyrics (LyricsHook.x), which
Native/Lyrics/LyricsCredit.x makes tappable. Tested on the Mac against harness/spicylyrics/.

## Make targets

    make build      # out/spoti.pw-<version>.ipa with FLEX in it
    make release    # the same without FLEX
    make install    # build without FLEX, sign with your certificate, install over USB
    make install FLEX=1   # the same with FLEX, which is what make trees reads through
    make trees      # record view trees screen by screen (FLEX build open on the phone, USB)
    make session    # clean trees, as many snapshots per screen as you like: Enter saves, n goes to the next screen
                    # (SCREENS="playlist artist" for some); every snapshot says whether the mod was at stock
    make log        # stream [spotifyglass] log lines from the phone
    make flags      # regenerate the flag table from the IPA

## Mod Settings

Mod Settings, opened by holding Home on the tab bar or from the first row of the side drawer and the
last row of Spotify's Settings, sorts every
setting by the part of Spotify it changes, so a part's glass, its hide switches and its flags sit on
one page, the mod's own rows first and Spotify's flags below them or on a sub page named after what
they change. It opens on the Appearance card: Redesigned UI, then the stored look's accent colour, and in the native
look AMOLED (the redesign is always black); Spotify's green is offered from the colour row once a colour
is set. Redesigned UI is the one switch between the two looks (see Layers): it glows
(Settings/SGGlowSwitch), its ⓘ says what it changes, and flipping it offers to restart Spotify.
The pages show only what the stored look has: a page opened after flipping the switch already shows
what the restart will bring. In the redesign Karaoke comes next, on a card of its own: Sing's switch and its
voice model's download (Redesigned/Lyrics/SingSettings.m), with Off, On, No model or the download's percentage
beside the row, "Needs iOS 18" below iOS 18. Sing needs no download: without the model it runs on the built-in separator (Shared/Sing/SGStemCenterSeparator.swift, which keeps what is centred in the stereo image above 150 Hz; harness/sing/center_test.py has its arithmetic), and the model's row reads "Built-in separator". Then a card of parts. Navbar: the tab editor of the stored look,
each with its own list of tabs. Lyrics, beside Player: the ordered list of lyrics sources, lyrics for every track,
naming the source in the redesign, the lock screen, and glass lyrics in the native look; in the redesign also
which of the lyrics, their pronunciation and their translation is set largest, and the translation's language.
Player: Gestures, Blocked artists (with the count on the row) and Lock screen widget (its controls and, under Artwork, Animated lock screen, the track's Canvas or the album's Apple Music cover played behind the lock screen's controls, on until switched off, with a Sources page for their order, and a "Needs iOS 26" row below that), which work with either look;
in the native look also Now playing bar (its device button and its flags), Queue & devices, and
Spotify's own player screen (artwork background, glass header buttons, Disable Canvas and the sheet,
header, slider and sticky header flags, the cards under the player and the lyrics preview and player
buttons to hide); in the redesign instead, right on the Player page, its device button and the Background behind the player: Fluid
artwork, the default, the cover itself Kawase blurred and warped on Metal, ported from kawarp (Redesigned/Kit/SGRWarp.m), or Animated
artwork, the track's Canvas or the album's Apple Music 3:4 cover looping muted over it (Redesigned/Player/PlayerAnimated.x), the square cover fading out as it fades in and back as it goes, found
the lock screen's way in an order of its own (a Sources page) and falling back to Fluid artwork for a track
without a clip, while one is fetched, while Spotify shows its own music video, and in Low Power Mode or with Reduce Motion on; the
choice is picked in place, applies at once and brings its own settings up under it: for Fluid artwork a live preview over Speed,
Warp, Blur, Saturation and Brightness, which the player follows as they move, and Reset; for Animated artwork its Sources; laid out against harness/kawarp/, the player's side against harness/player/ (its fluid and
animated scenarios). Then Vibrations under either look, a card for
Controls (on until switched off) and one for Music Haptics (off until switched on, with an ⓘ saying it
follows the sound this iPhone plays while Spotify is open), each opening out while its switch is on:
Controls into its Strength (10 to 100%, a tap at the new strength with each step), Music Haptics into its
Strength (20 to 200%, 100% being how it first shipped) and Follows, Everything (a tap on each kick and
snare and a rumble under the bass), Beat (the taps without the rumble) or Bass (the kicks' taps and the
rumble), all applying straight away. Live Activity, on iOS 17 and up under either look: its switch and which view it
shows, Lyrics, Queue or Control menu, both
applying straight away, the row reading out the view or Off. Audio effects, in either look (Shared/AudioEffects/AudioEffectsPage.m):
the effects' switch with what the engine is doing under it, then a card per effect, each opening out into its
sliders, choices, curve or file library while its switch is on, everything applying as it changes; the row reads
out Off, On or how many effects are on. Home & Library, in the native look only:
the Gradient page (the wash behind the top of Home in one of eight colours, at three strengths and
four heights) and the Home flags, the parts of Home to hide including the DJ button and badge, the
playlist header, buttons and pills to hide, and the Library flags. Then Privacy & clutter
(Block telemetry; hiding the video carousel and social proof in Search, and a Tips page under them,
every switch there forcing a flag Spotify ships on to off; then what the telemetry blocking has stopped) and Labs (features Spotify built and did not ship,
AI Chat (Martini) first). Last, All flags, Spotify's remote-config flags with a search field and an
Auto / Off / On control per flag (a text field for the number and text ones), and Mod: Updates
(the row reads out where the build stands and opens the changelog of everything newer than it, read
from the releases Release Please cuts, with Check now, the release to get, all the releases and Tell
me when one is out, the sheet a newer release brings up a few seconds after Spotify opens), the
build and Spotify's version, the site and the repo, the welcome tour again and Reset all
settings. A flag switch on a page forces that one flag and off leaves Spotify's own value, so the All
flags page is where a flag goes back to Auto. Spotify ships its newer design behind several flags at
once, and the redesign is built on it (the glass navigation bar, the new player slider, the sheet style
player, the queue and Connect sheets, the redesigned player header, the sleep timer's options sheet):
while Redesigned UI is on each is forced, over an override too, and their rows elsewhere show what is
forced and take no touch. `Redesigned/Kit/SGRGlassDesign.x` holds the list; what else forces a flag
registers in `Core/SGFlagForce.h`. A change shows after Spotify restarts.

The tab editor on the Navbar page is the exception and applies as soon as the bar lays out again. It lists the tabs in the order
the bar shows them: drag to reorder, tap to hide or show, and Add a tab opens a sheet that puts a page
of Spotify's or any `spotify:` link on the bar under a name of your own, with one of Encore's own glyphs
or an SF Symbol (the names come from `Core/SGSFSymbolCatalog.m`, MIT, on the Licenses page). Spotify's own tabs are kept by the
name under their icon, so they can be hidden but never removed, and switching the app's language
starts the order over. A tab of the mod's own opens its link through Spotify's link dispatcher, onto
the stack of the tab you are on. The redesign's glass bar lights it while that page is on the stack and
a second tap goes back to it; the native bar leaves the tab you were on lit. Hide labels, on the same page, leaves the glass bar with its
icons alone and applies straight away too.

## Adding a feature

1. `make trees`, record the screen, read `trees/<screen>.txt` for the classes and frames.
2. Decide the layer (see Layers), then make `tweak/Sources/<Layer>/<Feature>/` with `<Feature>.h` declaring the switch key
   (`#define SGKey<Feature> @"spotifyglass.<feature>"`) and `UIViewController *SG<Feature>SettingsPage(void)`.
3. Add the hooks in `<Screen>.x`: `#import "Core/SGCore.h"` and the feature header, guard on the
   switch, use `SGGlassFor`/`SGGlassAt` + `SGShapeGlass` for glass and `SGStripBackgrounds` to clear
   Spotify's paint, and end with `%ctor { %init; SGRequireClasses(@[...]); }`, gated first on the layer's look
   (`SGNativeUI()` or `SGRedesignedUI()`) in Native/ and Redesigned/.
4. Add `<Feature>Settings.m` returning an `SGModPage` of `SGSection`s of `SGSwitchRow`/`SGHideRow`/
   `SGFlagRow`/`SGChoiceRow`/`SGSliderRow` (Settings/SGModPage.h), and put it on the page of the part of
   Spotify it changes in `App/Pages.m` or `App/ModSettings.x`.
5. `make install`. Log lines are prefixed `[spotifyglass]`. A FLEX build serves the visible screen's
   tree on the phone's port 8085, which `make trees` reaches over USB through iproxy.

A class Spotify has renamed shows up in the log as `class X not found, its hooks are inactive`;
declare the classes a feature needs in `Headers/` only when a hook calls into them by type.
