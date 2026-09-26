# Sing feasibility and audio primitives

Sing is an opt-in implementation checkpoint. Model loading and source capture run concurrently;
preparation continues emitting the original audio while verified source read-ahead builds an
aligned vocal reserve. Preparing while paused loads the model; it does not separate an entire paused song.
The selected vocal level survives track changes. An expected next song can now be prepared from
Spotify's decoded continuous prefix while the current song's retained tail is still audible.
This boundary path has deterministic coverage; physical transition acceptance remains pending.
The existing Core AI GPU bundle needs a real background GPU grant, which was unavailable on the tested
iPhone even with an authorized signing profile. Core ML bundles use CPU inference in the background;
the optional adaptive mode also allows GPU inference while active in the foreground. The CPU path
has passed Mac audio/parity and simulator lifecycle checks, plus a physical
Spotify foreground/background/foreground test with the selected 70% level retained. Sustained
thermal, audible-continuity, track-transition and lock-screen acceptance remain outstanding.

## Audio and model integration

`Shared/Audio/SGAudioPipeline.x` owns Spotify's mixer connection and RemoteIO observation once.
Sing operates on 44.1 kHz stereo source samples before time/pitch processing; output processing
runs speed/pitch, upstream's AudioEffects engine, then music haptics in a fixed order. The audio callback exchanges
generation/track/source-frame/format-stamped packets with an asynchronous Swift worker through
bounded single-producer/single-consumer queues. Model loading, hashing and inference never run
on that callback. The reconstructed mix is `original - (1 - level²) * vocals`, clamped to
[-1, 1], with a 30 ms level ramp and a 120 ms return to aligned original audio.

`SGAudioSourceQueue.m` reads queue metadata only for the pinned Spotify 9.1.78 arm64 Mach-O UUID
and verified callback/reader signatures. It neither reads private PCM nor calls private functions.
The render consumer obtains samples through the existing AudioUnit source, pulling at most two
render quanta when verified spare audio is available, leaving a 120 ms native reserve. Pending commands,
stopping end markers and unstable metadata supply no extra budget. A known next track permits one
end marker only when the pinned reader's flags prove it can continue into the following PCM.
The original AudioUnit remains the sole consumer. A natural transition retains the worker and
buffered samples; a bounded clock-marker queue moves the audible clock at the actual sample boundary.
Explicit seek/skip, a different next-track identity and graph replacement invalidate the old generation.
The metadata scan stops after verifying the prefix needed for the current pull and native reserve;
it does not walk the rest of the buffered song on every render callback. A long-queue fixture
reduced kernel metadata reads from 260 to 44; grouping adjacent metadata fields now uses 32 for
the same prefix. These are fixture counts, not device energy measurements.
An exhausted, non-null block is skipped as the verified native reader does on its next pull;
an end marker requires the separate continuity checks above. Treating exhausted blocks as fences had prevented
read-ahead until Sing's reserve drained, repeatedly restoring original vocals even with fast
inference. The regression covers an exhausted head, following audio, real events and cycles.
Other binary layouts cannot attach Sing. The bounded eight-second timeline targets 5.5 seconds
of original audio ahead, emits dry audio immediately, and fades in vocal reduction only when
enough aligned future vocals are ready. Expired results never overwrite future ring-buffer slots.
Disabling stops extra pulls and drains the retained original in order before detaching.
During model loading, only the bounded playback timeline retains audio; the worker queue stays
empty, so a slow cold load cannot exhaust it. Once Ready, at most eight retained packets are
forwarded per callback. The worker skips only the initial samples already emitted as original
audio and starts inference at the live source cursor rather than processing an obsolete backlog.
The timeline rejects skips into future audio or any missing later hop. Worker idle polling is
25 ms and controller reconciliation is 100 ms; lyric and audio clocks remain render-driven.

The separator is Mel-Band RoFormer with the pinned third-party checkpoint below. Apple's
[Core AI](https://developer.apple.com/documentation/coreai/aimodel) supplies the execution runtime;
the project does not include Apple's Music Sing model. The exporter re-exports the original
eight-second graph at a fixed two-second shape rather than truncating the original graph's input.
It uses the pinned Core AI PyTorch exporter, FP16 tensors, static shapes, and standard attention
operations instead of the training implementation's flash-attention path. Attention and rotary
position operations remain in the exported graph instead of being externalized by the exporter.

The host reflects the PCM boundaries into `[1, 2, 201, 2048]` frames, calls the graph's `main`
function through `AIModel`, `InferenceFunction` and `NDArray`, then overlap-adds `recon` with
window-weight normalization. STFT/iSTFT are part of the graph. A separate overlap-add combines
two-second model windows with a 1.5-second hop and a 0.5-second overlap, reducing inference count
by one third relative to the original one-second hop. The Swift actors serialize inference even
across retiring generations; cancelled/obsolete results cannot enter a new track's mix. A loaded
model is kept warm for 60 seconds, while memory/thermal failures purge it.

The existing bundle uses the FP16 GPU-preferred graph, compiled ahead of time for the device
architecture. A bundle with `Backend = CoreMLCPU` instead loads `separator.mlmodelc` with
`MLModelConfiguration.computeUnits = .cpuOnly`; it cannot fall back to a GPU. Payload hashes,
architecture and tensor descriptors are validated before use. Both backends share the serialized
worker and streaming mixer. The model is a separately supplied `Sing.bundle`; weights, compiled
models and test audio are not committed or downloaded during playback. A missing or incompatible
bundle leaves Sing unavailable. Simulator model tests do not bypass the production hardware gate.

A bundle packaged with `--foreground-gpu` selects `CoreMLAdaptive`. It keeps a second Core ML
model configured with `.cpuAndGPU` for active foreground playback and the warm `.cpuOnly` model
for every inactive/background prediction. Both use the same graph, weights, FFT scratch and
source timestamps. Preparation warms the CPU path and, while active, the GPU path before Ready
while original playback continues.
If deactivation races with GPU submission, the adapter retries the same window on the CPU; it
suppresses repeated GPU retries until the app becomes inactive again. An optional GPU-load
failure leaves CPU processing available. A standalone iPhone fault test forced a stale foreground
decision during actual background execution. Apple's GPU permission error entered this fallback;
the same window finished on CPU within 0.824 seconds, and foreground acceleration resumed later.
All 101 windows completed without a missed deadline. The injected decision lived only in the
external test app; Spotify contains no fault injection. This mode does not change the default
CPU-only package or the existing Core AI backend; sustained foreground thermal validation is open.

The CPU export contains only the spectral separator (`SepCore` from the same pinned checkpoint).
Accelerate performs the 2,048-point periodic-Hann STFT and inverse on the worker, using reflected
boundaries, a 441-sample step and window-weight normalization. Core ML receives a float32 tensor
`[1, 2050, 201, 2]` and returns `vocals_spectrum` with that same layout. Moving FFTs out of the
graph avoids the full graph's dense transform layers. Reusable FFT plans and scratch belong to
the Core ML actor; model loading and synchronous prediction never run on UIKit or RemoteIO.
The actor also reuses its Core ML input tensor/provider and inverse accumulator. STFT writes
directly into that tensor, avoiding a separate 3.3 MB spectral allocation and copy per window.
One zero-input prediction warms the CPU model before the worker announces Ready, so first-use
allocation/specialization occurs while Spotify is still playing its original audio. The model
store shares that load and keeps it warm across seeks. Source read-ahead overlaps model loading;
inference builds the vocal reserve once loading completes. Original playback continues throughout.

With warm-up included in loading, the measured Mac run took 0.696–0.735 seconds per two-second window,
with cosine 0.999991 and RMS ratio 0.998898 against the reference, and about 1.70 GB peak RSS. The
iOS simulator produced the same audio but took 5.37–6.02 seconds per window: it passed conversion
correctness, not real-time feasibility. A physical iPhone 17 Pro test inside Spotify then processed
47 windows with a 1.134-second mean and 1.575-second maximum, including 20 windows during roughly
30 seconds on the Home Screen. The measured thermal state stayed nominal throughout. That short
test establishes CPU background execution, not endurance or locked-screen acceptance. A later
charging run reached 2.16–2.55 seconds per inference after returning to the foreground, exhausting
the eight-second recovery budget while thermal state was still fair. Original audio continued,
but the full-precision model could not sustain that load.

The selected CPU export now uses mixed precision: normalization, its denominator replication,
attention, softmax and matrix products stay FP32; the remaining eligible operations use FP16.
Keeping only normalization in FP32 failed parity. Keeping the denominator's `tile` in FP16
also produced non-finite output on silence because its 1e-12 floor rounded to zero. Both cases
were rejected. The selected profile keeps all seven operation types listed in `model.json`
at full precision, with FP32 inputs and outputs and CPU-only execution unchanged.

In the paired Mac audio benchmark, the mixed profile took 0.472–0.476 seconds per window versus
0.675–0.715 seconds for FP32, with cosine 0.999995 and RMS ratio 0.998743 against the reference.
Peak RSS fell from about 1.91 GB to 1.52 GB. Three short corpus excerpts changed SDR by at most
0.018 dB. Silence, quiet input, a silent stereo channel and boundary impulses produced finite
outputs; silence remained exactly zero. These are conversion/fixture checks, not a listening study.
A physical Spotify run then passed foreground/background/foreground and Off at 70%, with 46
windows averaging 0.780 seconds, a 1.479-second maximum and no missed 1.5-second hop deadlines.
The phone was charging and its thermal state remained fair. Diagnostic counters matched 457,230
original stereo sample values during preparation, with no mismatch or inserted silent buffers;
input and output counts both reached 3,165,792 source frames through activation and drain. Reduction started 5.184
seconds after source attachment; cold loading is additional. The longer follow-up was blocked
before activation by serious thermal pressure and an update prompt. A subsequent run with Xcode's
continuous screen recording disabled passed the 20–100% slider gestures, percentage labels and
selected collapsed icon, then hit the thermal safeguard after 34 inferences (0.957-second mean,
1.300-second maximum, no missed hop or playback-backlog error). Charging remained on, so this
does not isolate the separator's thermal contribution. A clean build using the reproducible
export then prepared while paused, held 70% for 60 seconds in the background, and regained
70% on an explicit next-track command in 5.47 seconds. Its 76 windows averaged 0.680 seconds
(maximum 1.718, one beyond the hop deadline). The second background interval ended at the
serious thermal safeguard, with no stream-backlog failure logged. This verifies an explicit
skip, not natural gapless transitions or endurance. The CPU profile remains marked
`deviceValidated: false` until sustained, natural-transition and locked-screen checks pass.
After input-buffer reuse, a further charging run entered recovery before the attempted natural
transition; the harness stopped on that intermediate state, followed by a serious thermal event.
That run does not establish a transition failure or a performance regression. The reuse change
passed identical golden/edge metrics and real-worker recovery under ASan/UBSan and TSan on the Mac;
its short paired timings and varying peak RSS do not establish an additional speed or memory gain.
A subsequent cool, unplugged two-minute foreground/background run stayed active without recovery.
However, a second unplugged foreground run at fair thermal state slowed to 1.59–2.42 seconds per
window and exhausted recovery after about a minute of active playback. Charging is therefore not
a sufficient explanation for the missed deadlines. Recovery now requires a full two-second vocal
reserve and retains its outage budget across brief reactivations; the deterministic regressions
pass, and that physical overload run no longer alternated repeatedly between dry and reduced
vocals. It still failed to sustain Sing. This is a recovery fix, not a throughput acceptance result.

The adaptive model-only iPhone probe completed 401 windows over ten minutes, including 364
windows in actual background state, without a missed 1.5-second hop deadline. Foreground
CPU/GPU predictions were about 0.30 seconds; background CPU predictions were about 0.53 seconds,
with a 0.848-second maximum during transition. Thermal state stayed fair. A GPU-only detached
run failed with Apple's background GPU permission error, so it is not a background alternative.
The production adaptive adapter passed native golden/edge checks and all four real-worker
activation, cancellation and recovery cases. Its first Spotify run still alternated original
vocals despite 0.29–0.41-second predictions, exposing the exhausted-block reader bug above.
After the reader fix, 149 seconds of physical foreground playback had no recovery or missed
hop deadline; the user confirmed continuously reduced vocals. That run ended at the serious
thermal safeguard, so it is not an endurance pass. A separate 295-second Spotify test passed
foreground/background/foreground, retained 70% and explicit Off, with no missed hop deadlines
(maximum inference 1.354 seconds). It included a system audio interruption and a natural track
transition. The next track reactivated Sing in about 3.8 seconds, after a 2.7-second original-audio
recovery at the preceding track's end. Thermal state stayed fair in that run. Seamless song
boundaries, locked-screen playback and sustained foreground thermal acceptance remain open.

Backend experiments and their acceptance status:

| Experiment | Observation | Decision |
| --- | --- | --- |
| Weight-only INT8, FP16 GPU | Reduced model/memory size; slower in the measured Mac comparison | Not promoted based on size alone |
| FP16 CPU | Failed the golden-output parity check | Rejected |
| INT8 weights with FP32 CPU activations | Passed parity; missed 43 scheduling deadlines in a five-minute isolated iPhone run, even at a longer 1.625-second hop | Rejected for live integration |
| Neural Engine preferred, INT8 or six-bit palettized | AOT compilation succeeded; first iPhone inference aborted with an ANE/MPSGraph runtime error | Rejected; the exact runtime cause remains unknown |
| Spectral Core ML FP16, CPU | Cosine 0.9318 and RMS ratio 0.9590 against the FP32 reference | Rejected |
| Spectral Core ML FP32, CPU | Parity and short background test pass; a later charging/foreground run exceeded the hop deadline and failed recovery | Retained as the full-precision comparison profile |
| Core ML fast-prediction specialization, FP32 CPU | No clear speed gain in the paired Mac run; higher load time and about 200 MB extra resident memory | Not adopted |
| Spectral Core ML mixed precision, CPU | Mac parity, numerical edge cases, worker recovery and short physical foreground/background test pass | Selected CPU candidate; prolonged and transition acceptance outstanding |
| Mixed Core ML, foreground CPU/GPU and background CPU | Ten-minute isolated iPhone probe completed 401 windows without missed deadlines; native parity and worker checks pass | Spotify validation in progress; GPU-only background execution was rejected by iOS |
| Mixed Core ML with CPU and Neural Engine allowed | A longer Mac probe completed preparation in 138 seconds and passed parity/edge inputs, but inference took 1.67–2.02 seconds per 1.5-second hop | Not promoted; slower on the Mac, and two isolated iPhone attempts terminated with signal 9 during preparation (cause unconfirmed) |

A Neural Engine preference does not prove an exclusively Neural Engine graph; the experimental
artifacts contained both ANE and MPSGraph regions. No rejected backend, diagnostic injection or
experimental native-buffer-size patch is included in the production path. The guarded metadata
reader above is distinct from the temporary source-callback feasibility probe.

## Checks

```sh
python3 harness/sing/test.py
TSAN=1 python3 harness/sing/test.py
python3 harness/sing/test_controller.py <booted-simulator-UDID>
python3 harness/sing/test_controller.py <booted-iOS-27-simulator-UDID> --background
python3 harness/sing/fetch_model.py --output /path/to/local/assets
xcrun swiftc -O -target arm64-apple-macos27.0 \
  tweak/Sources/Shared/Sing/SGStemCoreMLSeparator.swift \
  tweak/Sources/Shared/Sing/SGStemSeparator.swift harness/sing/benchmark.swift -o /tmp/sing-benchmark
/tmp/sing-benchmark /path/to/local/assets /tmp/sing-benchmark.json
```

The C test runs the production packet queue and mixer with wraparound, queue pressure, 100,000
concurrent transfers, generation/track/format rejection, gain ramps, limiting and audible-clock
arithmetic. The timeline test checks exact source order through buffering, circular wraparound,
aligned bypass and draining, plus cancellation before preparation and a worker outage. Recovery
requires the full ready-vocal reserve, rather than re-enabling reduction after a single late hop.
Its eight-second budget resets only after eight uninterrupted seconds of active playback, so
repeated short recoveries cannot keep alternating between reduced and original vocals forever.
Regression cases cover both that overload cycle and an unrelated stall after sustained recovery. The source
must stop pulling during a drain; only after the retained prefix is consumed may direct audio fill
the rest of a render buffer. The stream test exercises the actual source callback, worker packets,
pause, level updates, cancellation and bounded queue pressure. Original samples are emitted from
the first callback; vocal reduction waits for a full window of completed future vocals, so variations
in inference duration don't consume the entire bypass reserve. Production uses a two-second
window with a 1.5-second hop and a half-second linear
overlap: one third fewer inferences than the original one-second hop. A two-minute regression
holds inference at 1.3 seconds, as observed on a warm phone, and checks every original sample
through a longer preparation and every reduced sample after activation without entering recovery.
Tests also cover variable callback sizes, a temporarily depleted source queue, and a source with
no verified read-ahead, which must keep playing dry. Time to reduction still exceeds the original
three-second target; model load and sustained thermal performance require real-device measurement.
The cold-load regression plays 30 seconds of exact original samples through timeline wraparound
without worker input, then starts forwarding at the live cursor. The controller test uses the real lifecycle and stream with deterministic player, worker and
AudioUnit boundaries: thermal gating/recovery, drain-before-retry, normal worker completion before
the polling timer, model retention and cancellation during loading. It also covers preparing a
model while paused before an audio graph exists, cancelling that prepared model without waiting
for Play, waiting for the graph to appear after Play (with a bounded timeout), keeping 70% vocals
through a loading/track transition, continuing the expected next track and repeat-one with the same worker,
and preserving an explicit Off.
These tests do not constitute a live Spotify playback test.

Background ownership tests exercise entitlement and registration checks, asynchronous GPU grants,
actual processed-frame progress, cancellation, stale grants/expiration callbacks and submission
failures. The controller keeps the same worker when Spotify backgrounds with a grant; an expired
grant drains to the original audio. A temporary inactive state such as Control Center does not
cancel the worker. A device that reports no GPU support stops the worker in the background
without losing the selected level or repeatedly loading the model. Actual locked-screen/background
GPU execution still needs validation on a device that grants this resource.
The Core ML backends skip GPU-task registration and progress, keep the same session when the app
backgrounds, and rely on Spotify's existing audio background mode while playing. Simulator
controller tests cover backgrounding during loading, paused preparation, interruption/resume,
retained level and explicit Off without any GPU permission. Thermal, memory, route and source
format checks still apply. This lifecycle coverage does not prove physical locked-screen inference.
Temporary audio interruptions pause the worker's input and retain the loaded model and grant;
completion of model loading during the interruption cannot attach audio until it ends. Spotify's
own play state determines whether audio resumes. These cases are covered by the controller test.

The vocal level is clamped to 20–100%, with the same endpoints in the mixer, controller and slider.
If vocal coverage drops below the bypass reserve, the timeline fades to the aligned original
while the worker continues. Results that are already audible are discarded; future results
restore the chosen mix once a full two-second reserve is available. A single 2.2-second inference stall is
tested at original and reduced volume, including a pause during recovery. Every source sample
is emitted once, without another buffering pause. An eight-second recovery budget still drains to direct audio unless eight seconds of sustained
active playback first clears that outage; a brief reactivation does not reset the budget. The controller tests recovery without reloading and cancellation
during recovery; thermal, memory and format failures retain their existing safeguards.

The serial window worker also has a Swift concurrency test, including reset during an inference:

```sh
xcrun swiftc -g -sanitize=thread -strict-concurrency=complete -warnings-as-errors \
  tweak/Sources/Shared/Sing/SGStemWindowProcessor.swift harness/sing/window_test.swift \
  -o /tmp/sing-window-test
/tmp/sing-window-test
```

The C bridge also runs the real model with the production hop at 44.1 kHz callback cadence, checking sample order through
activation and a drain back to direct audio, then disabling during an in-flight inference:

```sh
python3 harness/sing/test_worker.py /path/to/short.aimodel /path/to/hashes.json /path/to/golden_raw.f32
```

This uses ASan/UBSan for the C stream, or `--tsan` to instrument both the Swift worker and C transport.
It also withholds one real inference result until the ready-vocal reserve actually depletes
(with a bounded timeout), then requires recovery within the stream's eight-second budget at
uninterrupted render cadence, with exact original sample order through bypass and return.
The model store retains a warm model for 60 seconds, shares a pending load, and invalidates expired
loads when unloaded. Inference on a shared warm function is serialized across retiring generations.
An additional cancellation case unloads during model preparation and requires Finished without
Ready, a failure callback or any source pulls. A cold-start case begins rendering during model
loading and verifies sample order through activation and cancellation. In the integrated adaptive
Mac run, Ready arrived at 11.698 seconds and reduction at 12.321 seconds, with original audio
from callback zero. This overlaps loading and read-ahead but does not meet a three-second cold
activation target. Earlier runs that waited for Ready before rendering took roughly 4.8–4.9 seconds
with FP32 or 3.8 seconds with mixed precision, excluding loading. These deterministic-source
measurements must not be presented as Spotify device startup or thermal acceptance.

The benchmark loads the real graph through the production Swift adapter, compares four inferences
to the pinned golden vocals, checks silence, quiet input, one silent channel and boundary impulses,
and reports load/inference time and peak resident memory. The model
and golden files stay local. The downloader verifies pinned Git blob or LFS hashes, uses atomic
replacement, and fetches only model/test assets. It never sends audio anywhere.

`model.json` records the conversion, checkpoint, weights and Core AI bundle revisions. The
published graph is fixed at 352,800 stereo samples (eight seconds). Its worst measured warm inference time
plus eight seconds of input collection is the lower bound for causal live activation; faster-than-
real-time inference alone cannot establish the specification's three-second requirement.

For the short-window prototype, re-export the pinned conversion's `SepFull2` with `frames` shaped
`[1, 2, 201, 2048]` (two seconds) or `[1, 2, 401, 2048]` (four seconds). Do not truncate input to the
eight-second artifact and call it a short-window export. Compare against the same checkpoint at
the same shape, then evaluate the production overlap-add sequence against the eight-second reference and
a listening corpus. The Swift adapter derives its window size from the actual graph descriptor.
Changing shape requires a new artifact, hashes and golden outputs.

For the CPU profile, `export_coreml.py` takes the same five positional paths as `export_model.py`.
It verifies source/checkpoint/golden provenance, traces the two-second spectral model, exports
the mixed-precision ML Program with the pinned Core ML tools version, and compiles it into
`separator.mlmodelc`. `--precision float32` exports the full-precision comparison model.
Keep enough free space for both the package and compiled weights. PyTorch 2.9 is newer than the
exporter's tested 2.8 support, so the trace and native golden checks are required; conversion
success alone is insufficient. New exports must match `cpuProfile.payloadHashes` (mixed) or
`cpuProfile.referencePayloadHashes` (FP32) before packaging. Two independent mixed-profile exports
produced identical graph and weight hashes; the native Swift benchmark also passed on that export.

Run the CPU parity and FFT round-trip checks with:

```sh
/tmp/sing-benchmark /path/to/cpu-assets /tmp/sing-cpu.json /path/to/cpu-assets/hashes.json separator.mlmodelc
xcrun swiftc -O -target arm64-apple-macos27.0 -strict-concurrency=complete -warnings-as-errors \
  tweak/Sources/Shared/Sing/SGStemCoreMLSeparator.swift \
  tweak/Sources/Shared/Sing/SGStemSeparator.swift harness/sing/spectral_test.swift -o /tmp/sing-spectral-test
/tmp/sing-spectral-test
python3 harness/sing/test_worker.py /path/to/cpu-assets/separator.mlmodelc \
  /path/to/cpu-assets/hashes.json /path/to/cpu-assets/golden_raw.f32
```

The FFT test covers independent stereo signals, DC, Nyquist, reflected boundary impulses,
scratch reuse and malformed/non-finite inputs. A benchmark's activation lower bound excludes
loading, the ready-vocal reserve and Spotify's source availability; it is never a live startup pass.

`export_model.py` exports either shape from pinned conversion and reference checkouts, the verified
checkpoint, and the original golden input. Its positional arguments name those four inputs and a
new output directory; `--seconds` is 2 or 4. Use the Core AI exporter revision in `model.json` and
its Python environment. Run `benchmark.swift` with the new directory, report path and `hashes.json`
as its third argument. The overlapped comparison uses the production window worker:

```sh
xcrun swiftc -O -target arm64-apple-macos27.0 \
  tweak/Sources/Shared/Sing/SGStemCoreMLSeparator.swift \
  tweak/Sources/Shared/Sing/SGStemSeparator.swift \
  tweak/Sources/Shared/Sing/SGStemWindowProcessor.swift harness/sing/overlap.swift -o /tmp/sing-overlap
/tmp/sing-overlap /path/to/short-assets /path/to/reference-assets /tmp/sing-overlap.json
```

`overlap` accepts an optional final hop length in samples, defaulting to 66150 for the two-second
model. Use 44100 for comparison with the original overlap; both compare the same central region.
`corpus.swift` takes the model, hashes, corpus directory, output directory and an optional hop length.
Its comparisons exclude the first second and final two seconds at either hop, so a longer final
output packet cannot improve its score by including different source samples.
The golden comparison measures conversion parity and context changes on one fixture. It cannot
replace a varied listening corpus, supported-device measurements or a real playback endurance run.

For a supported iPhone, AOT-compile the short artifact with `xcrun coreai-build compile` for the
device's architecture, then build the isolated UIKit runner with Xcode's configured signing team:

```sh
python3 harness/sing/build_device.py --model /path/to/compiled.aimodelc \
  --goldens /path/to/short-assets --team YOUR_TEAM_ID
```

For a cloud-synced checkout, add `--build-dir /path/to/local-cache/sing-device` so Finder metadata
does not invalidate code signing. This directory is replaced on subsequent builds.

Install the resulting app using `xcrun devicectl device install app`. The bundle identifier is
`pw.spoti.harness.sing`. Launch it with `-duration 1800` for a 30-minute model load test, or without
arguments for eight inferences. Add `-waitForCool YES` to wait up to ten minutes for Nominal before
loading; with `devicectl process launch`, put `--` before these app arguments. The runner uses a dark
screen and schedules one inference every 1.5 seconds, matching the production hop. Pass
`-hopSeconds 1` to compare the old cadence. Reports include the requested hop and model source hash;
deadline misses include accumulated scheduling lateness. It records initial and final thermal state, cadence
misses, parity, peak RSS and the minimum remaining process memory allowance. It stops at Serious
or Critical heat and if it leaves the foreground. `Documents/progress.json` updates every ten
windows; `Documents/result.json` contains the completed result, retrievable with `devicectl device
copy from --domain-type appDataContainer`. The app contains only the supplied test goldens and
model; it does not capture audio or perform a Spotify playback test.

Before live integration, prove an aligned dry/processed bypass. Dropping a delayed queue when
disabling would jump forward; replaying already-audible source when enabling would jump backward.
The supplied specification explicitly excludes shipping that behavior. An eight-second diagnostic
result must not enable the production microphone control.

## Model provenance

The full-screen view, lyrics host, header, footer, controls and hosting controller names were
verified in the user-supplied Spotify **9.1.78** IPA. No Spotify binary or lyrics are committed.

Model provenance is pinned in [the manifest](model.json):

* [Conversion](https://github.com/john-rocky/coreai-model-zoo/tree/5029e6df8100650fe175d3e276fffb0177754ca1/conversion/melband_roformer).
* [Core AI artifact](https://huggingface.co/mlboydaisuke/MelBandRoformer-Vocal-CoreAI/tree/06f257a0d1d2ee4938595f872a23e9fc4c3fc97d), model card explicitly tagged MIT.
* [Checkpoint](https://huggingface.co/KimberleyJSN/melbandroformer/tree/ac9b0614ab3cd7f77219e18ba494dfd93956c348), weight repository explicitly tagged MIT.
* The host graph contract was checked against [KitSeparator](https://github.com/john-rocky/coreai-kit/blob/0a5933611ce91206d287b61ecdb94b5ec726b65e/Sources/CoreAIKit/Separation/KitSeparator.swift).

Attribution: Mel-Band RoFormer by Ju-Chiang Wang, Wei-Tsung Lu and Minz Won; the vocal checkpoint
by KimberleyJensen; lucidrains' BS-RoFormer implementation; ZFTurbo training code; the Core AI
conversion by john-rocky. Model weights, compiled artifacts and golden audio are not part of the
tweak package. A future package containing them must preserve the applicable MIT notices.


## Local Spotify build

`package_model.py MODEL.aimodelc out/Sing.bundle --architecture h18p` packages the
local two-second export, hashes every AOT payload, and includes the model's notices
and pinned provenance. Compile `export_model.py`'s output for the device with
`coreai-build` first. No model or test audio belongs in Git.
Pass the verified `separator.mlmodelc` instead to package the CPU candidate. Its graph and weights
must match one of the pinned CPU profiles. The target architecture remains explicit even though Core ML
can specialize its compiled model on several devices; that does not certify those devices for Sing.
Add `--foreground-gpu` when packaging that Core ML model to enable adaptive foreground GPU / background CPU
execution. Omitting it keeps CPU-only execution. Both options use the same pinned spectral payloads.

Pass `SING_MODEL_BUNDLE=/absolute/path/to/Sing.bundle` to the existing
`scripts/pipeline.sh` or `make release`. The normal build remains usable without
that optional resource. In the redesigned look, enable **Lyrics → Sing** and
restart Spotify. The microphone appears in the lyrics overlay opened by Now Playing's lyrics button;
its slider changes the running mixer without reloading the model. Unsupported
OS/hardware or a missing resource explains why Sing is unavailable.

The Core AI GPU backend also requires **Background GPU Access** on the app's signing target and a
provisioning profile that authorizes `com.apple.developer.background-tasks.continued-processing.gpu`.
The entitlement alone is insufficient: `BGTaskScheduler.supportedResources` must also contain
`.gpu` on the actual device. When it does not, the current GPU model cannot continue in the
background; adding or refreshing the signing profile does not remove that restriction.
`configure_background.py` adds the bundle-specific Sing task identifier and preserves Spotify's
existing background modes/identifiers. The pipeline and installer run it before signing; custom
signers that change the bundle ID must run it with `--bundle-id NEW_ID` before signing, too.
For a CPU bundle it preserves the existing modes/identifiers without adding GPU-task configuration.
It does not grant an entitlement. iOS owns the task's progress/cancellation interface and can
expire its GPU grant; Sing then returns to the original audio. No inference runs on the audio thread.

The player integration now owns loading, 44.1 kHz stereo attachment, pause,
seek/track invalidation, thermal and memory fallback, and delayed-original drain.
Spotify's position getter, karaoke and the system now-playing elapsed time use
the same emitted-source clock while the adapter is attached. Device validation
of this integration, transitions between tracks and routes, and the 30-minute
thermal/continuity acceptance run are still required before release.
