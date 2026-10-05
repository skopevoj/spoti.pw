# Spicy Lyrics harness

`Shared/LyricsSources/SpicyLyrics.m` compiled and run on the Mac, on the real line model
(`KaraokeTiming.m`) and `SGTTML.m`, with the request answered by the test (`stubs.m`) and the
source's defaults kept in memory.

    ./build.sh

The fixtures are the three shapes the developer platform documents (`Syllable`, `Line`, `Static`)
from each `source` (`spicy_lyrics` with and without a maker, `apple_music`, `spotify`, `unknown`),
in placeholder words. The test checks the lines, backing vocals, duet sides, overlapping lines,
pronunciation and translation, the credit the terms require, the key's validation, and what the
source does on a 401/403 (the row's text, no further requests), a 404 (kept), a 429 and a 503
(waited out, counted as lost so the walk asks again).

What it cannot check is the live API with a real key: whether a publishable key with No origin
header allowed is accepted from the phone, and the rate limit's real numbers.
