#!/usr/bin/env python3
"""Run the production worker at PCM cadence, including disable during inference (macOS 27)."""
import argparse
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("model", type=Path)
parser.add_argument("hashes", type=Path)
parser.add_argument("golden_raw", type=Path, help="planar stereo float32, 44.1 kHz")
parser.add_argument("--tsan", action="store_true")
args = parser.parse_args()
here = Path(__file__).resolve().parent
src = here.parent.parent / "tweak/Sources"
out = here / "build/worker"
out.mkdir(parents=True, exist_ok=True)
flags = ["-sanitize=thread"] if args.tsan else []
subprocess.run(["xcrun", "swiftc", "-O", "-strict-concurrency=complete", "-warnings-as-errors",
                "-target", "arm64-apple-macos27.0", "-emit-library", *flags,
                *(str(src / "Shared/Sing" / name) for name in
                  ["SGStemCoreMLSeparator.swift", "SGStemSeparator.swift", "SGStemWindowProcessor.swift", "SGStemWorker.swift"]),
                "-o", str(out / "libStemWorker.dylib")], check=True)
cflags = ["-fsanitize=thread"] if args.tsan else ["-fsanitize=address,undefined"]
subprocess.run(["xcrun", "clang", "-std=c11", "-Wall", "-Wextra", "-Werror", "-g", "-O1", *cflags,
                "-I", str(src), "-x", "c", str(here / "worker_test.c"),
                *(str(src / "Shared/Sing" / name) for name in
                  ["SGSingStream.m", "SGSingTimeline.m", "SGSingDSP.m"]),
                str(src / "Shared/Audio/SGAudioRingBuffer.m"), "-L", str(out), "-lStemWorker",
                "-Wl,-rpath," + str(out), "-o", str(out / "worker-test")], check=True)
command = [str(out / "worker-test"), str(args.model.resolve()), str(args.hashes.resolve()), str(args.golden_raw.resolve())]
subprocess.run(command, check=True)
subprocess.run([*command, "205"], check=True)
subprocess.run([*command, "2000", "stall"], check=True)
subprocess.run([*command, "--cancel-loading"], check=True)
subprocess.run([*command, "--cold"], check=True)
