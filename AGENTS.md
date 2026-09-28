# spoti.pw

A Theos tweak (Objective-C + Logos) injected into the decrypted Spotify iOS app. The full guide is
`docs/tweaks.md`; read it before changing code.

## Two looks, never both

**Redesigned UI** (Mod Settings → Appearance) picks one of two looks, read once at launch:

- **Native**: Spotify's own screens with the mod's tweaks on them (hide switches, glass header buttons,
  Home gradient, AMOLED switch, accent colour...).
- **Redesigned**: the mod's own Liquid Glass look, from a clean sheet. It includes the glass tab bar,
  search field and now playing bar, the redesigned player and lyrics page with Apple Music style lyrics
  always on, a decluttered Home, Search's categories on tinted glass, a Library with one large title, the
  playlist, album and artist pages the way the Music app lays them out with one pinned ⋯ over each, black
  throughout, and its own accent colour. No native tweak runs.

Anything that doesn't draw on Spotify's screens works the same under both: privacy, lyrics
sources, gestures, blocked artists, flags, Vibrations, Speed and pitch, and the Live Activity. Those
last three were the redesign's until they moved to `Shared/`, so their keys lost the `.redesign.` and
`Core/SGPrefs.h`'s `SGMigrateKey` carries the old ones over at launch.

**The redesign is tested on iOS 26 only.** It is Liquid Glass, which the system draws from 26 on;
below that `SGRedesignTested()` (`Core/SGUIMode.h`) answers NO and the switch and the tour's card warn
before it is picked (`SGRedesignUntestedWarning()`). The redesign runs there only when
`SGKeyRedesignUntested` was set along with the switch, so one stored before the warning is dropped at
launch. The native look's floor is iOS 16.1, which is Spotify 9.1.78's own.

## Where code goes (`tweak/Sources/`)

| Layer | What | Gate at the top of every `%ctor` |
|---|---|---|
| `Shared/` | behaviour and data, either look | none |
| `Native/` | Spotify's screens tweaked | `if (!SGNativeUI()) return;` |
| `Redesigned/` | the redesign (`Kit/` + parts) | `if (!SGRedesignedUI()) return;` |
| `App/` | Mod Settings root and combined pages, Mod page, tour | none |
| `Core/`, `Settings/`, `Headers/`, `Diagnostics/` | infrastructure | none |

Rules:

- Imports run one way: `Core <- Settings <- Shared <- Native | Redesigned <- App`. Native and
  Redesigned never import each other. `scripts/check-layers.sh` runs before every build and fails on a
  violation. Don't work around it.
- Change one look without touching the other. When both need the same thing, each side keeps its own
  copy under its own names (`SG…` native, `SGR…` redesign) and its own keys. Examples are the tab bar
  composition and editor, AMOLED and the accent colour. Don't merge copies back into
  a shared file.
- A lower layer that needs something from a higher one gets it through a registry in `Core`
  (forced flags: `Core/SGFlagForce.h`) or a function declared low and defined high.
- Settings: each layer builds its own rows and sections. `App/Pages.m` and `App/ModSettings.x`
  decide what to show from `SGRedesignedUIStored()`, so native-only pages disappear in the redesign.
- Keys start with `spotifyglass.` (redesign-only ones with `spotifyglass.redesign.`). Switches are
  read at launch, so a change needs a restart.

## Working on it

- Build: `make install` (signs and pushes to the phone), `make release` (IPA only). Tweak only:
  `env -u MAKELEVEL gmake -C tweak clean package`.
- Look at Spotify's views through recorded trees (`make session` records clean ones into
  `trees/clean/`) before hooking anything. Prove every class and selector against the tree or the binary.
- Device log: `make log` (`[spotifyglass]` lines).
- Releases: Release Please (`.github/workflows/release.yml`). Commit as `feat:` / `fix:` (they bump
  `version.txt` and fill `CHANGELOG.md`; `chore:`, `refactor:` and `docs:` stay out). Merging its
  release PR tags `vX.Y.Z` and attaches the `.deb`. Never edit `version.txt` by hand. `beta` releases
  `vX.Y.Z-beta.N` pre-releases the same way (`release-please-config.beta.json`); only beta builds are
  offered them. When `beta` merges into `main`, keep `main`'s `version.txt`.
- Moving to a new Spotify version: change `SGSupportedSpotifyVersion` in `Settings/SGPageStyle.m`. Any
  other version gets the "isn't supported" alert and red row (`App/About/Compatibility.m`), so a bump
  without it warns everyone. Update the README (badge and text), `.github/ISSUE_TEMPLATE/bug_report.yml`,
  the iOS floor above and the web's `content/site.ts` with it. `Shared/Audio/SGAudioSourceQueue.m` pins
  the 9.1.78 binary by UUID and offsets and stands down on any other until they are read off again.
- Known traps: anything pushed onto Spotify's nav stack must conform to `SPTPageController`
  (`Settings/SGPage.m`). Setting `hidden` on views inside Spotify's `OverflowStackView` or its Encore
  stacks crashes, so use alpha. A `CADisplayLink` capped at 60 Hz drags the player's 120 Hz
  transitions down with it. Glass takes the appearance it inherits, and outside Spotify's navigation
  stacks (the tab bar, the now playing bar, the player) that is the system's: set every pane of the
  mod's to `overrideUserInterfaceStyle = UIUserInterfaceStyleDark`, or it goes light in light mode.

## Ending a task

The owner runs about ten sessions at once, each on a different task, and reads each final message with
no context. End every task with what they have to do next to verify it, as the last thing in the
message: one sentence, or a short list when there are several steps. Make it stand on its own: the
command to run (`make install`, a restart), which look and iOS version, which screen to open, and what
should look or behave differently. When nothing needs checking on their side, say so in one line.
