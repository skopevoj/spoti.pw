# Sing

Sing turns a song's vocals down, anywhere from 20 to 100 %, while Spotify plays it, from the
redesigned player's lyrics. The vocals are separated on the iPhone by a Core ML export of
Mel-Band RoFormer; no audio leaves the phone. It needs iOS 27.

## Audio and model integration

`Shared/Audio/SGAudioPipeline.x` owns Spotify's mixer connection and RemoteIO observation once.
Sing operates on 44.1 kHz stereo source samples before time/pitch processing; output processing
runs speed/pitch, the audio effects engine, then music haptics in a fixed order. The audio callback
exchanges generation/track/source-frame/format-stamped packets with an asynchronous Swift worker
through bounded single-producer/single-consumer queues. Model loading and inference never run on
that callback. The reconstructed mix is `original - (1 - level²) * vocals`, clamped to [-1, 1],
with a 30 ms level ramp and a 120 ms return to aligned original audio.

`SGAudioSourceQueue.m` reads queue metadata only for the pinned Spotify 9.1.78 arm64 Mach-O UUID
and verified callback/reader signatures. It neither reads private PCM nor calls private functions.
The render consumer obtains samples through the existing AudioUnit source, pulling at most two
render quanta when verified spare audio is available, leaving a 120 ms native reserve. Pending
commands, stopping end markers and unstable metadata supply no extra budget. A known next track
permits one end marker only when the pinned reader's flags prove it can continue into the
following PCM. The original AudioUnit remains the sole consumer. A natural transition retains the
worker and buffered samples; a bounded clock-marker queue moves the audible clock at the actual
sample boundary. Explicit seek/skip, a different next-track identity and graph replacement
invalidate the old generation. The metadata scan stops after verifying the prefix needed for the
current pull and native reserve; it does not walk the rest of the buffered song on every render
callback. An exhausted, non-null block is skipped as the verified native reader does on its next
pull; an end marker requires the separate continuity checks above. Other binary layouts cannot
attach Sing.

The bounded eight-second timeline targets 5.5 seconds of original audio ahead, emits dry audio
immediately, and fades in vocal reduction only when enough aligned future vocals are ready.
Expired results never overwrite future ring-buffer slots. Disabling stops extra pulls and drains
the retained original in order before detaching. During model loading, only the bounded playback
timeline retains audio; the worker queue stays empty, so a slow cold load cannot exhaust it. Once
Ready, at most eight retained packets are forwarded per callback. The worker skips only the
initial samples already emitted as original audio and starts inference at the live source cursor
rather than processing an obsolete backlog. The timeline rejects skips into future audio or any
missing later hop. Worker idle polling is 25 ms and controller reconciliation is 100 ms; lyric and
audio clocks remain render-driven.

If vocal coverage drops below the bypass reserve, the timeline fades to the aligned original
while the worker continues. Results that are already audible are discarded; future results
restore the chosen mix once a full two-second reserve is available. An eight-second recovery
budget drains to direct audio unless eight seconds of sustained active playback first clears that
outage; a brief reactivation does not reset the budget. Thermal (serious or worse), memory and
format failures stop Sing and keep the original audio playing.

## The model

The separator is Mel-Band RoFormer with the pinned third-party checkpoint below, exported by
`export_coreml.py` as the model's spectral core alone (`SepCore` of the pinned conversion). The
worker performs the 2,048-point periodic-Hann STFT and its inverse with Accelerate, using reflected
boundaries, a 441-sample step and window-weight normalization (`SGStemSpectralDSP.swift`). Core ML
receives a float32 tensor `[1, 2050, 201, 2]`, `spectrum`, and returns `vocals_spectrum` in the
same layout: two seconds of audio per prediction. Reusable FFT plans, the input tensor and the
inverse accumulator belong to the separator's actor; model loading and prediction never run on
UIKit or RemoteIO.

The streaming worker overlap-adds two-second windows with a 1.5-second hop and a 0.5-second
linear overlap. One zero-input prediction on each loaded copy warms the model before the worker
announces Ready, so first-use allocation happens while Spotify still plays its original audio.
The model store shares that load, keeps it warm for 60 seconds across seeks and songs, and purges
it on memory or thermal pressure.

The same compiled model is loaded twice: once with `.cpuOnly`, used whenever Spotify is not the
active app (iOS refuses GPU work from the background), and once with `.cpuAndGPU`, used while it is.
If backgrounding races a GPU submission, that window is retried on the CPU with its timestamp
kept, and the GPU is not asked again until Spotify has been inactive. A GPU copy that fails to
load leaves the CPU one doing everything.

The export uses mixed precision: normalization, its denominator replication, attention, softmax
and matrix products stay FP32 (the seven operation types in `model.json`), the rest FP16. Keeping
only normalization in FP32 failed parity, and an FP16 `tile` made silence non-finite because its
1e-12 floor rounded to zero. In the paired Mac benchmark the mixed model took 0.472–0.476 seconds
per window against 0.675–0.715 for FP32, with cosine 0.999995 and RMS ratio 0.998743 against the
reference, and peak RSS fell from about 1.91 GB to 1.52 GB. Three short corpus excerpts changed SDR
by at most 0.018 dB; silence, quiet input, a silent channel and boundary impulses stay finite, and
silence stays exactly zero. These are conversion checks, not a listening study.

On an iPhone 17 Pro a ten-minute model-only probe of the CPU/GPU pair completed 401 windows,
364 of them in the background, without missing a 1.5-second hop: about 0.30 s per window in the
foreground and 0.53 s in the background. Inside Spotify, 149 seconds of foreground playback ran
without recovery, and a 295-second run passed foreground, background and foreground again, kept
70 % and an explicit Off, and crossed a natural track transition, with a 1.354-second worst window.
A CPU-only model could not sustain Sing in the foreground once the phone was warm (1.59–2.42 s per
window), which is why the GPU copy exists. Seamless song boundaries, locked-screen playback and a
sustained thermal run are still open, so `deviceValidated` in `model.json` stays false.

Experiments and their outcome:

| Experiment | Observation | Decision |
| --- | --- | --- |
| Spectral Core ML FP16, CPU | Cosine 0.9318 and RMS ratio 0.9590 against the FP32 reference | Rejected |
| Spectral Core ML FP32, CPU | Parity and a short background test pass; a warm foreground run missed the hop deadline | Kept as the full-precision comparison export |
| INT8 weights with FP32 CPU activations | Passed parity; missed 43 deadlines in a five-minute isolated iPhone run | Rejected |
| Core ML fast-prediction specialization, FP32 CPU | No clear speed gain; slower loading and about 200 MB more resident memory | Not adopted |
| Mixed precision, CPU and Neural Engine | 1.67–2.02 s per 1.5 s hop on the Mac; two iPhone attempts ended with signal 9 while preparing | Not adopted |
| Mixed precision, CPU only | Parity, edge cases and worker recovery pass; too slow in the foreground once warm | Superseded by the CPU/GPU pair |
| Mixed precision, CPU/GPU in the foreground and CPU in the background | Ten-minute iPhone probe without a missed deadline; Spotify runs above | Used |

## Checks

```sh
python3 harness/sing/test.py                 # DSP, timeline and stream, ASan/UBSan
TSAN=1 python3 harness/sing/test.py          # the same under ThreadSanitizer
python3 harness/sing/test_controller.py <booted-iOS-27-simulator-UDID>
python3 harness/sing/fetch_goldens.py        # golden_raw.f32 and golden_vocals.f32 into build/goldens
python3 harness/sing/test_worker.py /path/to/separator.mlmodelc harness/sing/build/goldens/golden_raw.f32
```

The C tests run the production packet queue, mixer, timeline and stream: wraparound, queue
pressure, 100,000 concurrent transfers, generation/track/format rejection, gain ramps, limiting,
exact source order through buffering, aligned bypass and draining, cancellation before
preparation, a worker outage, variable callback sizes, a depleted source queue and a source with no
verified read-ahead, which must keep playing dry. Recovery requires the full ready-vocal reserve,
and a two-minute regression holds inference at 1.3 seconds, as observed on a warm phone, checking
every original sample through preparation and every reduced sample after activation.

The controller test runs the real lifecycle and stream with deterministic player, worker and
AudioUnit boundaries on an iOS 27 simulator: thermal gating and recovery, drain before retry,
worker completion before the polling timer, model retention, cancellation while loading,
preparing while paused before an audio graph exists, waiting a bounded time for the graph after
Play, keeping 70 % through a loading/track transition, continuing the expected next track and
repeat-one with the same worker, interruptions, backgrounding, and an explicit Off. It is not a
live Spotify playback test.

The worker test runs the real model through the production stream at 44.1 kHz callback cadence,
checking sample order through activation and a drain back to direct audio, disabling during an
in-flight inference, a withheld result that forces recovery (which must end within the stream's
eight-second budget), unloading while the model prepares, and rendering from the first callback
while the model loads cold. Add `--tsan` to instrument both the Swift worker and the C transport.

The serial window worker and the FFT have Swift tests of their own:

```sh
xcrun swiftc -g -sanitize=thread -strict-concurrency=complete -warnings-as-errors \
  tweak/Sources/Shared/Sing/SGStemWindowProcessor.swift harness/sing/window_test.swift -o /tmp/sing-window-test
/tmp/sing-window-test
xcrun swiftc -O -target arm64-apple-macos27.0 -strict-concurrency=complete -warnings-as-errors \
  tweak/Sources/Shared/Sing/SGStemSeparator.swift tweak/Sources/Shared/Sing/SGStemSpectralDSP.swift \
  harness/sing/spectral_test.swift -o /tmp/sing-spectral-test
/tmp/sing-spectral-test
```

The FFT test covers independent stereo signals, DC, Nyquist, reflected boundary impulses, scratch
reuse and malformed or non-finite input.

`benchmark.swift` loads the model through the production separator, compares four predictions to
the two-second goldens `export_coreml.py` writes next to its export, checks silence, quiet input,
one silent channel and boundary impulses, and reports load and inference time and peak memory.
`overlap.swift` compares the overlapped two-second windows with the eight-second reference goldens
`fetch_goldens.py` fetches, and `corpus.swift` scores the separation against a local corpus of
stems (`manifest.json` of mixes and vocals); both take an optional hop length, 66150 by default.

```sh
S=tweak/Sources/Shared/Sing
xcrun swiftc -O -target arm64-apple-macos27.0 $S/SGStemSeparator.swift $S/SGStemSpectralDSP.swift \
  harness/sing/benchmark.swift -o /tmp/sing-benchmark
/tmp/sing-benchmark export/separator.mlmodelc export /tmp/sing-benchmark.json
xcrun swiftc -O -target arm64-apple-macos27.0 $S/SGStemSeparator.swift $S/SGStemSpectralDSP.swift \
  $S/SGStemWindowProcessor.swift harness/sing/overlap.swift -o /tmp/sing-overlap
/tmp/sing-overlap export/separator.mlmodelc harness/sing/build/goldens /tmp/sing-overlap.json
```

`build_device.py` builds a standalone iPhone app that runs the model on the goldens every 1.5
seconds, with Xcode's development team: `--model`, `--goldens`, `--team`, and `--build-dir` outside
a cloud-synced folder. Install it with `xcrun devicectl device install app`; launch it with
`-duration 1800` for a 30-minute run, `-waitForCool YES` to wait for a nominal thermal state first,
or `-hopSeconds 1` for another cadence. It stops at serious heat or when it leaves the foreground,
and writes `Documents/progress.json` and `Documents/result.json`. It runs no Spotify and no audio.

## Exporting

`export_coreml.py` takes the pinned conversion and reference checkouts, the checkpoint, the
original golden input and a new output directory. It verifies their provenance, traces the
two-second spectral model, converts it with mixed precision, compiles it into `separator.mlmodelc`
and prints its payload hashes, which must match `export.payloadHashes` (or
`referencePayloadHashes` for `--precision float32`). Two independent exports produced identical
hashes. PyTorch 2.9 is newer than the exporter's tested 2.8, so the trace and golden checks are
required; conversion alone proves nothing.

The pinned coremltools `9.1.dev1` is not on PyPI. With the public releases, export with
`--unpinned-tools`: in a separate virtual environment, torch 2.9.0, coremltools 9.0 and numpy
below 2.3 (numpy 2.5 makes coremltools 9.0 fail on a one-element cast), plus einops 0.6.1,
beartype 0.14.1, rotary_embedding_torch 0.3.5, librosa and pyyaml. Such an export's
`weights/weight.bin` matches the pinned hash and only `model.mil` differs; on the golden window it
gave cosine 0.999995 on the CPU and 1.000000 on CPU+GPU against PyTorch, and `test_worker.py` passed
with it.

```sh
python harness/sing/export_coreml.py zoo ref MelBandRoformer.ckpt build/goldens/golden_raw.f32 export --unpinned-tools
```

The model the app downloads is that public-tools export (`export.unpinnedPayloadHashes`).

## The model on the phone

The model is not in the IPA. In the redesigned look, **Mod Settings → Karaoke**
has Sing's switch, which puts the microphone in the player's lyrics and takes it away at once (off,
Sing does no work), and the voice model's row: Not downloaded, Downloading 43 % · 210 of 467 MB with
a bar under it and Cancel download, Checking…, Downloaded · 467 MB with Remove voice model, or
Paused / Download failed, whose tap says why. Below iOS 27 the section is a "Needs iOS 27" row.

`Shared/Sing/SGSingModel.m` downloads the five files of `separator.mlmodelc` one by one from
`https://huggingface.co/Darkkos/spoti-sing/resolve/main/<path>` (no archive: iOS has no public
unzip) and pins each file's size and SHA-256 in its table; nothing the server says about them is
trusted. It checks for free space first (the model plus 64 MB), asks before using a cellular or Low
Data Mode network, and otherwise keeps off them and waits for Wi-Fi. The download runs in a
background `URLSession`, so it goes on while Spotify is away; the app delegate is given
`application:handleEventsForBackgroundURLSession:completionHandler:` for it (Spotify's has none), and
a launch reconnects to a download left running by the session's identifier. Each file lands in
`Library/Application Support/spoti.pw/Sing/Download/`, is hashed off the main thread and named there
only if it is the pinned one; a file that is not is deleted and stops the download. Cancel keeps each
file's resume data, and Download goes on from it (a resume that fails starts that file over, once).
Once every file is in, the staged `separator.mlmodelc` becomes
`Library/Application Support/spoti.pw/Sing/separator.mlmodelc` in one rename, and the folder is
excluded from the iCloud backup. Remove deletes the folder and drops the warm model. The controller
loads the model from there; without it Sing is unavailable and the lyrics show no microphone.

```sh
python3 harness/sing/stage_model.py export/separator.mlmodelc build/spoti-sing
python3 harness/sing/model_test.py build/spoti-sing
```

`stage_model.py` makes the folder to upload to the model repository, the model's files at their
paths with `NOTICE` and a model card, and prints the manifest the way `SGSingModel.m` pins it,
saying whether the code pins that one; a new export needs the table replaced before it ships.
`model_test.py` serves such a folder on localhost and runs the production download code against it
in a real background session on the Mac (ASan/UBSan): a corrupted `model.mil` rejected and deleted, a
cancel at 100 MB resumed from where it stopped (the server sees the range), the install, a download
left running by one process and picked up by the next, and removal.

## Model provenance

The full-screen view, lyrics host, header, footer, controls and hosting controller names were
verified in the user-supplied Spotify **9.1.78** IPA. No Spotify binary or lyrics are committed.

Model provenance is pinned in [the manifest](model.json):

* [Conversion](https://github.com/john-rocky/coreai-model-zoo/tree/5029e6df8100650fe175d3e276fffb0177754ca1/conversion/melband_roformer).
* [Golden input and vocals](https://huggingface.co/mlboydaisuke/MelBandRoformer-Vocal-CoreAI/tree/06f257a0d1d2ee4938595f872a23e9fc4c3fc97d), model card explicitly tagged MIT.
* [Checkpoint](https://huggingface.co/KimberleyJSN/melbandroformer/tree/ac9b0614ab3cd7f77219e18ba494dfd93956c348), weight repository explicitly tagged MIT.

Attribution: Mel-Band RoFormer by Ju-Chiang Wang, Wei-Tsung Lu and Minz Won; the vocal checkpoint
by KimberleyJensen; lucidrains' BS-RoFormer implementation; ZFTurbo training code; the conversion
by john-rocky. Model weights, compiled models and golden audio are not part of the tweak package,
and anything that ships them keeps the MIT notices in `NOTICE`.
