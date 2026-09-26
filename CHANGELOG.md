# Changelog

## [0.22.1](https://github.com/skopevoj/spoti.pw/compare/v0.22.0...v0.22.1) (2026-09-26)


### Fixes

* Remove leftover debug line that reshows update notice every launch ([425d68b](https://github.com/skopevoj/spoti.pw/commit/425d68bc1761e90a6b5828864720511bcef79fa9))

## [0.22.0](https://github.com/skopevoj/spoti.pw/compare/v0.21.1...v0.22.0) (2026-09-23)


### Features

* Apple Music's animated album cover on the lock screen where the track has no Canvas ([e0d5538](https://github.com/skopevoj/spoti.pw/commit/e0d55383bc26149d7f3f5c803d07df0d0cf0e8bc))
* audio effects run on the mod's own engine, libjamesdsp is gone ([413b2d3](https://github.com/skopevoj/spoti.pw/commit/413b2d3e5647822961b3f9eed317c9accf729a4c))
* find in playlist as a glass search bar above the header, shown on pull-down ([#81](https://github.com/skopevoj/spoti.pw/issues/81)) ([36ed0a7](https://github.com/skopevoj/spoti.pw/commit/36ed0a798fb2f7756e8e62f2e0ee893b8329a1b8))
* line meanings from Genius on the lyrics, a bubble for the artist's own and an underline for the rest, opened in a sheet ([950baf7](https://github.com/skopevoj/spoti.pw/commit/950baf778f6aa342176f293bc2ab00f0e960640a))
* Mod &gt; Licenses shows the mod's license and the full text of the third-party ones ([c790445](https://github.com/skopevoj/spoti.pw/commit/c790445c70fcf6d0dea07b9550fa6d64a7fb87b7))
* play the track's Canvas as the lock screen's animated artwork ([c4b75e3](https://github.com/skopevoj/spoti.pw/commit/c4b75e3785de5a49407cd6762fb8cc30c26cf5fa))
* the artist's Follow is a glyph that turns into a checkmark, as add to library does ([#88](https://github.com/skopevoj/spoti.pw/issues/88)) ([f10bf8d](https://github.com/skopevoj/spoti.pw/commit/f10bf8d88e7d4a126ad143a77280999a64ab1c58))


### Fixes

* a long note under a settings section shows in full instead of ending in an ellipsis ([a6b1876](https://github.com/skopevoj/spoti.pw/commit/a6b187684356c83dad10cda2213f933886d6cc69))
* add to library turns into a checkmark, and Follow no longer flips from a glyph to a word ([#86](https://github.com/skopevoj/spoti.pw/issues/86), [#88](https://github.com/skopevoj/spoti.pw/issues/88)) ([e524034](https://github.com/skopevoj/spoti.pw/commit/e524034ed886ff624761ca2299940d7b143e380f))
* the player's more menu no longer hangs on loading and greys out lyrics for tracks no source has lyrics for ([#93](https://github.com/skopevoj/spoti.pw/issues/93)) ([283ac30](https://github.com/skopevoj/spoti.pw/commit/283ac308180468a1e124a3fb1e7a2ab9633d9241))
* the playlist's cover keeps its size and its fade after the page is pulled down past the top ([a83562c](https://github.com/skopevoj/spoti.pw/commit/a83562cd928fa7a710d8a28ddd32c9e7486a0fa7))
* the redesigned player can no longer be scrolled up ([#83](https://github.com/skopevoj/spoti.pw/issues/83)) ([62eee33](https://github.com/skopevoj/spoti.pw/commit/62eee3363981310b0e3d3c79e60acb2f9c309182))

## [0.21.1](https://github.com/skopevoj/spoti.pw/compare/v0.21.0...v0.21.1) (2026-09-21)


### Features

* a replayed welcome tour brings the donate sheet too ([7ddf0bf](https://github.com/skopevoj/spoti.pw/commit/7ddf0bf93d6f45faed74b9751ece758521bbf0a8))
* offer the donate sheet after the first tour ([cb7bf69](https://github.com/skopevoj/spoti.pw/commit/cb7bf69db0d3582c8d77aaa52ac0d0c5e830190b))
* support the project on Ko-fi ([b796643](https://github.com/skopevoj/spoti.pw/commit/b796643a5220c36cd556070d6279cb5fe05d7d45))


### Fixes

* Recents with Block telemetry on, lyrics cache eviction, protobuf length overflow, Set rule types, Live Activity update order ([4b21bed](https://github.com/skopevoj/spoti.pw/commit/4b21bed034953c9786521101da9f96197f949b90))
* trim the Lyrics settings page ([76b8577](https://github.com/skopevoj/spoti.pw/commit/76b85776d1b6c4306ade9f2c84cd8039cbae4b55))
* trim the Mod Settings descriptions ([79572ae](https://github.com/skopevoj/spoti.pw/commit/79572ae06b2a606f69d8314d87d57d302e1d0999))


### Chores

* release 0.21.1 ([f864787](https://github.com/skopevoj/spoti.pw/commit/f864787a474ac6225d99bebd4e67d312e0136ab8))

## [0.21.0](https://github.com/skopevoj/spoti.pw/compare/v0.20.0...v0.21.0) (2026-09-21)


### Features

* add check update endpoint ([f2a163c](https://github.com/skopevoj/spoti.pw/commit/f2a163cde6c95fa613baeeb652ec1de19bc14236))
* line-timed lyrics light line by line, plain lyrics show unsynced ([#61](https://github.com/skopevoj/spoti.pw/issues/61)) ([fa0ae4f](https://github.com/skopevoj/spoti.pw/commit/fa0ae4f02746c6312a7fad4cbcca8aeb4b2f50a2))
* the download button shows waiting, progress and downloaded, and shuffle is white when off ([#65](https://github.com/skopevoj/spoti.pw/issues/65)) ([f8d0e43](https://github.com/skopevoj/spoti.pw/commit/f8d0e433b39a2912128a169b09f5fd82474a12f6))


### Fixes

* a navbar tab opens its page instead of "can't open this type of link" ([#66](https://github.com/skopevoj/spoti.pw/issues/66)) ([b2288b3](https://github.com/skopevoj/spoti.pw/commit/b2288b320ca635744d0d52a712efd1e1ed6cba53))
* a playlist with the Mix feature on shows its picture instead of a black header ([59b8299](https://github.com/skopevoj/spoti.pw/commit/59b82990d17f044a1b98476d0927a5f3ea1811c7))
* an artist, album or playlist opened for the first time fills its hero when the picture lands ([1eb52fb](https://github.com/skopevoj/spoti.pw/commit/1eb52fb8f546c8563d0c4fba8e39455d9fe1e99d))
* artisti skip performance optimizations ([96bad59](https://github.com/skopevoj/spoti.pw/commit/96bad59eec5dfc397c760af26e602c2cb9d1977a))
* nothing of the mod ticks against a screen that is off ([0685135](https://github.com/skopevoj/spoti.pw/commit/0685135d669fb6709105f338859c78df56c0590d))
* rename auto update ([355b087](https://github.com/skopevoj/spoti.pw/commit/355b087b85fe61eec5a5872b9d6af28257a1c9a3))
* rename built ipa from workflow ([4e0292d](https://github.com/skopevoj/spoti.pw/commit/4e0292dbd882cd1cf4fb01de56d333089beae694))
* Sort and Mix are on the ⋯ sheet the first time it opens ([def7470](https://github.com/skopevoj/spoti.pw/commit/def7470a3428ab7b6193581048ae8d6e6f33edd8))
* the ⋯ menu's Speed and pitch row is white from its first frame ([#68](https://github.com/skopevoj/spoti.pw/issues/68)) ([ee97535](https://github.com/skopevoj/spoti.pw/commit/ee97535e0e2d1308783fda2650e489751a0ec8cf))
* the library sorts again, the entity pages keep their ⋯, and a creator opens from the line that names them ([7af6610](https://github.com/skopevoj/spoti.pw/commit/7af66109391860a53779ca8f829d8c0027935392))
* the player's background follows the playing track, and moves in its colours ([#58](https://github.com/skopevoj/spoti.pw/issues/58), [#59](https://github.com/skopevoj/spoti.pw/issues/59)) ([a70fe1a](https://github.com/skopevoj/spoti.pw/commit/a70fe1a01d30ae2ca7d6d6de40deda89788011a3))
* the player's lyrics, connect and queue row sits lower ([#54](https://github.com/skopevoj/spoti.pw/issues/54)) ([7b3308a](https://github.com/skopevoj/spoti.pw/commit/7b3308a22d48f3dd025c76980fadb5de4f98b337))

## [0.20.0](https://github.com/skopevoj/spoti.pw/compare/v0.19.0...v0.20.0) (2026-09-20)


### Features

* a release newer than the build says so on its own, a few seconds after Spotify comes up ([cf29254](https://github.com/skopevoj/spoti.pw/commit/cf292542ccfcc0ef15d63d49433742d1077eb029))
* Audio effects in Mod Settings, JamesDSP's switch and a card per effect with its sliders, curve or file library ([e41002b](https://github.com/skopevoj/spoti.pw/commit/e41002b1aec18466c6aafe257b3bcfd495ce9152))
* JamesDSP's effects on everything Spotify plays, run on each buffer its output unit finishes ([546245e](https://github.com/skopevoj/spoti.pw/commit/546245ee73073009ac89da0571e4d66272a912bc))
* lyrics sung at once lit together, dots through an instrumental break, and a line's pronunciation and translation ([669a0a5](https://github.com/skopevoj/spoti.pw/commit/669a0a5dbc0ce48397f36a8c319e0e99f0e62caf))
* Spicy Lyrics as a lyrics source, matched by Spotify's track id and timed to the syllable ([1d28754](https://github.com/skopevoj/spoti.pw/commit/1d28754aa19252800627acab4e98900a0403740d))
* the redesign is offered only on iOS 26, and what does not need its glass works under both looks ([1bbfca2](https://github.com/skopevoj/spoti.pw/commit/1bbfca2235187d9dfb13bc3cf085f7b5e070cc24))
* the Updates page, the changelog of every release newer than the build, read from the repo's GitHub Releases ([bca0efe](https://github.com/skopevoj/spoti.pw/commit/bca0efeb77e55544d694f8971e7a305d0e011add))
* Vibrations settings, a strength for the controls' taps and for Music Haptics, and what Music Haptics follows ([94058a0](https://github.com/skopevoj/spoti.pw/commit/94058a06536f8ca3a21d3d7a920564b0bfc489c0))


### Fixes

* a playlist Spotify makes shows its picture again instead of a black hero ([419d9dd](https://github.com/skopevoj/spoti.pw/commit/419d9ddb41f775d377efb5610496d461106ade9e))
* lyrics in right-to-left scripts sit against the right edge and are sung from the right, on the lyrics page and in the Live Activity ([61bd8ee](https://github.com/skopevoj/spoti.pw/commit/61bd8eedc90368a1bddecbf1f54e5381de6c8af2))
* Spicy Lyrics gives its word timing now the request carries the desktop client's identity ([c3d3047](https://github.com/skopevoj/spoti.pw/commit/c3d3047fc025264ed823d9a1aa0e9a5bec41d1a6))
* Spicy Lyrics gives its word timing now the request carries the desktop client's identity ([61febbe](https://github.com/skopevoj/spoti.pw/commit/61febbec110d351efd718e1a999f1e4b6bf28dbf))
* the add to library button shows the first time an album or playlist opens ([4ae246f](https://github.com/skopevoj/spoti.pw/commit/4ae246fb58d1b8ec1fd42cdc081690090ed798c1))
* the episode page and the playlist's Recommended songs no longer paint black bands over the page colour ([2edcb6c](https://github.com/skopevoj/spoti.pw/commit/2edcb6cede3b8d1d4868d92688189a9a7082b19f))
* the library's header buttons no longer land on its title when the page first opens ([4e5c576](https://github.com/skopevoj/spoti.pw/commit/4e5c57669c12a28a654b13bd641b5ba9d67c96c7))
* the now playing bar stays clear of the tab bar on a phone with a home button and under Offline or Private Session ([927b1c6](https://github.com/skopevoj/spoti.pw/commit/927b1c6a4b9229117e66150367b9f489448b47fc))
* the tab bar, the now playing bar and the mod's glass stay dark when the phone is in light mode ([1b83288](https://github.com/skopevoj/spoti.pw/commit/1b832882485d7f1fe0d50bd005f7a706ac969f8e))

## [0.19.0](https://github.com/skopevoj/spoti.pw/compare/v0.18.0...v0.19.0) (2026-09-18)


### Features

* albums and singles get the playlist's header, the Kit's own view over Spotify's blanked column ([307ba51](https://github.com/skopevoj/spoti.pw/commit/307ba514564ff481b4f1084cc6e43b4927c34400))
* the artist page gets the playlist's and album's header and loses its videos and tab strip ([57a2833](https://github.com/skopevoj/spoti.pw/commit/57a28330325c3e8f29e44c7274db85c31d90e832))
* the player grows out of the now playing bar's card and the cover flies out of its artwork, the way the Music app opens its player ([9eebe8d](https://github.com/skopevoj/spoti.pw/commit/9eebe8d8912902c0d4d1848dcfe2ba8413ec6dcd))
* the playlist header is the redesign's own, laid out like the Music app's, fed by the page's view model ([986c35d](https://github.com/skopevoj/spoti.pw/commit/986c35d29df3e8c095b76d3ac441b7a2c1aa6577))


### Fixes

* a lyrics walk that lost a request to a failure is not kept as "no lyrics" for the session ([4814a50](https://github.com/skopevoj/spoti.pw/commit/4814a506920b9ac3595e2b1dfd202db7a941ddb0))
* the artist page opens again, with more left in Spotify's row and drawn by the redesign in the top corner ([48b7eba](https://github.com/skopevoj/spoti.pw/commit/48b7ebaaf212de1d69fe45f567b8cb938119e99a))
* the artist page's liked row, carousels and See more fade no longer paint black bands over its colour ([1349340](https://github.com/skopevoj/spoti.pw/commit/134934027f7d66eb0478551114f6093dfaa5eb50))
* the home screen widget shows what is playing again, Spotify's App Groups moved into one the re-signed IPA has ([4b63f35](https://github.com/skopevoj/spoti.pw/commit/4b63f3599eb55efccd37d0e5162dd4c13d4e355a))
* the now playing bar and the tab bar keep their glass while the player closes, live glass behind Spotify's rendered stand-ins ([f1d184d](https://github.com/skopevoj/spoti.pw/commit/f1d184d416d4b7d337af643cb10c1c7d9f207ebc))

## [0.18.0](https://github.com/skopevoj/spoti.pw/compare/v0.17.0...v0.18.0) (2026-09-18)


### Features

* add backup settings ([daaf445](https://github.com/skopevoj/spoti.pw/commit/daaf445de51e72cd54fd599b5773c6fe9bba3056))
* add live activity lyrics ([94360e9](https://github.com/skopevoj/spoti.pw/commit/94360e98f6c1b06ad96fa43fb4674ae2f84ffdc1))
* add LRCLIB as the floor under the other lyrics sources ([ab78945](https://github.com/skopevoj/spoti.pw/commit/ab78945ecc114e3057af446c9d233d3e8f54cd1b))
* add new record trees flag ([8bbdb6e](https://github.com/skopevoj/spoti.pw/commit/8bbdb6e4eb224df8a7835586848df642068450db))
* Apple Music style lyrics only in the redesign and always on there, the native karaoke copy gone, and AGENTS.md and CLAUDE.md for agents ([cc24a25](https://github.com/skopevoj/spoti.pw/commit/cc24a25e29eaee1b103ca4019747884d3b3793b3))
* declutter the album page and put its blurred cover behind the header ([f414321](https://github.com/skopevoj/spoti.pw/commit/f414321444edb8e8261429677c42560f420c93fd))
* declutter the artist page and fade its photo into a blur ([d169287](https://github.com/skopevoj/spoti.pw/commit/d1692876dcd2f7290cff6da4e5d4f46cb2560f10))
* Home's shortcut tiles hold their cover inset on a surface tinted faintly by it, instead of the stretched blur ([3de8ea1](https://github.com/skopevoj/spoti.pw/commit/3de8ea1431ebca3243c72a282108c829dfadcb71))
* lyrics from a list of sources you put in order, and the word timing CJK always had ([e0e0076](https://github.com/skopevoj/spoti.pw/commit/e0e0076609927a44f9886c4fd07554eda844a297))
* lyrics from Musixmatch, with word timing from NetEase ([f640a2f](https://github.com/skopevoj/spoti.pw/commit/f640a2fd180b557bfe79f2663ed73cdcf70b0733))
* lyrics from the sources for tracks Spotify has none for ([11e6536](https://github.com/skopevoj/spoti.pw/commit/11e6536a42f83fc5fef6eb0052aff489afbcc5a4))
* navbar hide labels ([d4ebbd0](https://github.com/skopevoj/spoti.pw/commit/d4ebbd026879ba6e3a023576004f285bcbe6ba30))
* now playing hide device ([73f07e5](https://github.com/skopevoj/spoti.pw/commit/73f07e5652f9d8226458d4e8f304dc4938d31a0a))
* one Redesigned UI switch in place of Liquid Glass UI, glowing, with what it changes behind its info button ([2f8a8b8](https://github.com/skopevoj/spoti.pw/commit/2f8a8b81b54b3056ce887c17320bad14c3fc82f9))
* open Mod Settings by holding Home on the tab bar ([cd42edf](https://github.com/skopevoj/spoti.pw/commit/cd42edf49b5331292cf0594618770686a1b0c8de))
* pick the native or the redesigned player from tabs on the Player page, and drop the artist redesign ([21df22c](https://github.com/skopevoj/spoti.pw/commit/21df22cd6bbf223b51c83fd9912f29cb8b9ce0e8))
* put the blurred cover behind the playlist header ([c3039da](https://github.com/skopevoj/spoti.pw/commit/c3039dacf3b62c199c42a51b0528ba7c81a58619))
* put the sung line in the system now playing instead of a Live Activity ([0a75065](https://github.com/skopevoj/spoti.pw/commit/0a750651b5efd31c8944f28fdbf4c70eed08c479))
* record clean view trees screen by screen, each marked with the mod's settings ([98ba047](https://github.com/skopevoj/spoti.pw/commit/98ba047a5d71b791be5676202d9d6e7805fd9726))
* redesigned Home, decluttered to music on black, and a hang sampler for FLEX builds ([7168f76](https://github.com/skopevoj/spoti.pw/commit/7168f76919b6d0ee9a595060d59e869e190838f4))
* redesigned player and artist page behind their own switches (work in progress) ([bacc0df](https://github.com/skopevoj/spoti.pw/commit/bacc0df4be3a4f62689a3a9ca72b82b0919276ed))
* redesigned Search, the Browse page down to its categories on Liquid Glass tinted by their own colour ([e18311b](https://github.com/skopevoj/spoti.pw/commit/e18311b771520312b8631397809abb44c8c6c8cf))
* releases cut by Release Please with the .deb attached, and the … ([4f6fcdd](https://github.com/skopevoj/spoti.pw/commit/4f6fcdd16c82044463c065fcb4ed18e4a9c19bb3))
* releases cut by Release Please with the .deb attached, and the Updates row asks GitHub for the latest one ([349c5cf](https://github.com/skopevoj/spoti.pw/commit/349c5cf2c338fd58e44a248b2525608a932304c6))
* smooth the karaoke word sweep and lift ([dba0bcc](https://github.com/skopevoj/spoti.pw/commit/dba0bcc20971ef62754f833a5be4612f99af231e))
* soften the iOS 27 blur band under the top bar ([b7ca59e](https://github.com/skopevoj/spoti.pw/commit/b7ca59e275d5f9d40ec01dc99e0cde5085a904b6))
* speed and pitch sliders in the redesigned player's more menu, done on Spotify's audio between its mixer and its output ([c3fccc1](https://github.com/skopevoj/spoti.pw/commit/c3fccc1040f416f9f2b9a2faad4b806de1845c83))
* split Home & Library settings into Playlists, Library, Album and Artist pages ([927ed34](https://github.com/skopevoj/spoti.pw/commit/927ed34b6980e74da1b5e004e0a68469a3cc2cac))
* sweep the lyrics card under the player word by word too ([3dab9e9](https://github.com/skopevoj/spoti.pw/commit/3dab9e9a91bdd3cf071910d24937406a5800e3cf))
* the line being sung as a Live Activity in the redesign, on the lock screen and in the Dynamic Island ([900a64a](https://github.com/skopevoj/spoti.pw/commit/900a64ae5265c2142e32f66cb950ba9f02f8324e))
* the Live Activity on a page of its own, showing the lyrics, the queue or a control menu ([01111bb](https://github.com/skopevoj/spoti.pw/commit/01111bbf858171a4e9066ae37eede197f03c8f19))
* the lyrics in the redesigned player itself, the way the Music app shows them, and the player one screen that does not scroll ([d58d811](https://github.com/skopevoj/spoti.pw/commit/d58d811e58efc87f989940c9c4816e148e9dea06))
* the redesign always black with an accent colour of its own, and a restart offered when Redesigned UI flips ([8b43d26](https://github.com/skopevoj/spoti.pw/commit/8b43d264023c83693acbb8c8570075f63307d9ed))
* the redesigned album page, the Music app's layout laid over Spotify's own, and nothing under the tracks but the album itself ([dd8f4cd](https://github.com/skopevoj/spoti.pw/commit/dd8f4cdba7c319ecb33c3dfac8670b6e6daa64e2))
* the redesigned library, one large title and no filter pills over Spotify's own list ([63b5f12](https://github.com/skopevoj/spoti.pw/commit/63b5f12fc08f853dca157a9af49591290c2b3c4d))
* the redesigned playlist page, the Music app's layout laid over Spotify's own header ([87a8cd9](https://github.com/skopevoj/spoti.pw/commit/87a8cd92192c0dbfd6f9549a155404ea610b56df))
* the Redesigned UI switch shows its rainbow while off, and its ⓘ says in two lines what each look is ([b828ce1](https://github.com/skopevoj/spoti.pw/commit/b828ce138f90faef8ef04ecf6a883031aea26c3f))
* the welcome tour as a pick between the redesign and the legacy look, with Hold Home for settings ([083395b](https://github.com/skopevoj/spoti.pw/commit/083395b050f898bdb9f6a0e74f80a44915036340))
* the welcome tour down to one page, Redesigned UI offered switched on ([9dd74bf](https://github.com/skopevoj/spoti.pw/commit/9dd74bfa43f4554efb56f65e5954deb5db5e8d4c))
* the welcome tour warns the redesign is a beta, with a link to report bugs ([83b1fd3](https://github.com/skopevoj/spoti.pw/commit/83b1fd36dcfcff4bc26b72e11cf12efc1baca8ba))
* turn the redesigned player's play glyph at the tap, and keep the Player page's shared rows above the player tabs ([53ebda6](https://github.com/skopevoj/spoti.pw/commit/53ebda6959ef47e87dd454548edbe4aac5cb35f4))
* Vibrations in the redesign, taps for the player's controls and Music Haptics played along with the song ([387533d](https://github.com/skopevoj/spoti.pw/commit/387533dcdc60b68698c8b5ae1d860f77ac0a2a1e))


### Fixes

* clean up now playing settings ([ee23334](https://github.com/skopevoj/spoti.pw/commit/ee23334271e56214628bb6d504298d4a77684ca7))
* flashing hiding components ([2a74f83](https://github.com/skopevoj/spoti.pw/commit/2a74f83c3c90acb00d05a6375cec7d7aa8cadb03))
* gather App Intents protocols with the flag Xcode 26 swiftc accepts ([4d0328a](https://github.com/skopevoj/spoti.pw/commit/4d0328aa05bda5f8d2b235392dcd0ad40f17c8a4))
* Home's shelf headings held on Spotify's own label instead of a frame ([bbaaf50](https://github.com/skopevoj/spoti.pw/commit/bbaaf501f92a19c34f390f383195e079f826b486))
* keep the karaoke fade over the lines as the page scrolls ([7f4ea5d](https://github.com/skopevoj/spoti.pw/commit/7f4ea5d66cf337b9ca35b50d466bccefec0e2f68))
* Liked Songs laid out like a playlist, its title centred, Shuffle Play in the middle with its glyph, and no blue band as it scrolls ([b203f20](https://github.com/skopevoj/spoti.pw/commit/b203f20e9cd5463a029fba7064ad40dc64c13b90))
* pipeline issue ([1dd3070](https://github.com/skopevoj/spoti.pw/commit/1dd30701146ca52f3dda44a2d38ed397f88ada61))
* pipeline makelevel ([6895a4e](https://github.com/skopevoj/spoti.pw/commit/6895a4e19f3b895dc54b67bd1d361b2393a2ffa6))
* the album page's black band under the title as it scrolled, and its field taking Spotify's colour where Spotify has one ([8dc7a7f](https://github.com/skopevoj/spoti.pw/commit/8dc7a7f0ef98d84ee00bd533d7ed1af5c2968ab3))
* the playlist's action row half arranged after opening, its buttons moved by a transform Spotify's layout leaves alone ([9dd784e](https://github.com/skopevoj/spoti.pw/commit/9dd784e11e9f242b503a16724722f200655cdbe8))
* the playlist's colour wash and play disc back over the picture after pressing Play ([8666f7b](https://github.com/skopevoj/spoti.pw/commit/8666f7b4300c6da841930c59783c267b069c540b))
* the playlist's picture stopped short of the title, and Spotify's play disc showed while the page opened ([3007e05](https://github.com/skopevoj/spoti.pw/commit/3007e0564651149508bddf90d446e0caca52b666))
* udpate makefile to support .swift ([82bb7b5](https://github.com/skopevoj/spoti.pw/commit/82bb7b54e4016a80f8915e99cf7e77d189b833c8))


### Performance

* karaoke line views for the lines in sight only, and no blur on the card ([28f2323](https://github.com/skopevoj/spoti.pw/commit/28f23235688d486c424343ca68de6a9f5999b282))
* let the player open and close smoothly with the karaoke card under it ([103cf88](https://github.com/skopevoj/spoti.pw/commit/103cf886f6f354fae0b6d02cc4000c7868a2247b))
* measure the karaoke song off the main thread and make its line views a few a frame ([9bbec02](https://github.com/skopevoj/spoti.pw/commit/9bbec027c3ca6308b7d2f09addafa61e3563d28a))
