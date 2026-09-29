# Third-party code of the audio effects

Built by `Makefile` into `build/<platform>/libsgaudio.a`, which `tweak/Makefile` links. Only the files the
effects compile are here, each unchanged, with its project's license beside it.

| Directory | What for | Upstream | Commit | License |
|---|---|---|---|---|
| `libbs2b/` | Crossfeed | github.com/alexmarsev/libbs2b: `src/bs2b.c`, `bs2b.h`, `bs2btypes.h`, `bs2bversion.h` | `5ca2d59888df047f1e4b028e3a2fd5be8b5a7277` | MIT (`COPYING`) |
| `wdl/` | Liveprog (EEL2, portable bytecode, no JIT) | github.com/justinfrankel/WDL: `WDL/eel2/nseel-compiler.c`, `nseel-eval.c`, `nseel-ram.c`, `ns-eel.h`, `ns-eel-int.h`, `ns-eel-addfuncs.h`, `glue_port.h`; `WDL/wdltypes.h`, `wdlcstring.h`, `utf8_extended.h`, `denormal.h` | `8f4d783de745126ac8c201455dc30818c8613324` | zlib (`LICENSE`) |

`eel2-parser/` is spoti.pw's own code, not third party: EEL2's parser written by hand from `eel2.y`'s grammar,
and `rand()`. Upstream's `y.tab.c`/`y.tab.h` are Bison output (GPL with Bison's exception) and its
`nseel-cfunc.c` carries a Mersenne Twister, so neither is here.
