# Audio pipeline

```sh
python3 harness/audio/test.py
TSAN=1 python3 harness/audio/test.py
```

Runs the production pipeline against a deterministic Core Audio boundary on macOS, with
ASan/UBSan or ThreadSanitizer. Checks processor order, bounded source pulls, sample times,
silent buffers, failure after consuming input, connection/callback replacement, unsupported
formats, and disposal while rendering. The render thread must never wait for graph changes.
Sing coverage checks uninterrupted reduced samples across a natural song boundary and concurrent
clock reads that must never pair one song's identity with the other song's position. Queue tests
verify one traversable end marker, stopping flags, signature changes and the next marker's fence.

The real RemoteIO/effect tests remain in `harness/speed`, `harness/audio-effects/sim`, and
`harness/haptics/sim`. These boundary tests do not establish device playback or Sing performance.
