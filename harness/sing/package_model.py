#!/usr/bin/env python3
"""Package a pinned two-second Core AI or Core ML export; never downloads a model."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("model", type=Path, help="compiled .aimodelc or .mlmodelc separator")
parser.add_argument("output", type=Path, help="new Sing.bundle directory, outside tracked source")
parser.add_argument("--architecture", required=True, help="target device's Core AI architecture name, e.g. h18p")
parser.add_argument("--foreground-gpu", action="store_true", help="Core ML: GPU in foreground, warm CPU in background")
args = parser.parse_args()
source, output = args.model.resolve(), args.output.resolve()
if source.suffix not in (".aimodelc", ".mlmodelc") or not source.is_dir() or output.exists() or output.name != "Sing.bundle":
    parser.error("need a compiled model and a new Sing.bundle output")
if not args.architecture.isalnum():
    parser.error("invalid target architecture")
here = Path(__file__).resolve().parent
manifest = json.loads((here / "model.json").read_text())
cpu = source.suffix == ".mlmodelc"
if args.foreground_gpu and not cpu:
    parser.error("--foreground-gpu requires a Core ML model")
backend = ("CoreMLAdaptive" if args.foreground_gpu else "CoreMLCPU") if cpu else "CoreAI"
metadata = json.loads((source / "metadata.json").read_text())
if cpu:
    profile = manifest["cpuProfile"]
    if not isinstance(metadata, list) or len(metadata) != 1 or metadata[0].get("license") != "MIT":
        parser.error("the pinned model must retain its MIT metadata")
    actual = {}
    for name in profile["payloadHashes"]:
        with (source / name).open("rb") as stream:
            actual[name] = hashlib.file_digest(stream, "sha256").hexdigest()
    if actual not in (profile["payloadHashes"], profile["referencePayloadHashes"]):
        parser.error("Core ML graph or weights differ from the pinned CPU exports")
    source_hash = actual["model.mil"]
else:
    profile = manifest["liveProfile"]
    if not (source / f"main-{args.architecture}.mlirb").is_file():
        parser.error("architecture does not match the compiled graph")
    if metadata.get("license") != "MIT" or metadata.get("sourceHash", "").upper() != profile["sourceHash"].upper():
        parser.error("AOT graph is not the pinned MIT two-second export")
    source_hash = metadata["sourceHash"]
output.mkdir(parents=True)
try:
    destination = output / ("separator" + source.suffix)
    # clonefile avoids duplicating model storage on APFS, with independent destination ownership.
    if sys.platform == "darwin":
        subprocess.run(["cp", "-cR", str(source), str(destination)], check=True)
    else:
        shutil.copytree(source, destination)
    hashes = {}
    for path in sorted(destination.rglob("*")):
        if path.is_symlink():
            raise ValueError("model payloads must be regular files")
        if path.is_file():
            with path.open("rb") as stream:
                hashes[path.relative_to(destination).as_posix()] = hashlib.file_digest(stream, "sha256").hexdigest()
    (output / "hashes.json").write_text(json.dumps(hashes, indent=2) + "\n")
    (output / "Sing.plist").write_bytes(plistlib.dumps({"Architecture": args.architecture, "WindowFrames": 88200,
        "Backend": backend, "SampleRate": 44100, "Channels": 2, "SourceHash": source_hash}))
    (output / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "pw.spoti.sing-model",
        "CFBundlePackageType": "BNDL", "CFBundleVersion": "1"}))
    for name in ("NOTICE", "model.json"):
        shutil.copyfile(here / name, output / name)
except BaseException:
    shutil.rmtree(output)
    raise
print(output)
