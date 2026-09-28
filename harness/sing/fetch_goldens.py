#!/usr/bin/env python3
"""Fetch the pinned golden input and vocals (export_coreml.py, test_worker.py, benchmark.swift), verifying each."""
from pathlib import Path
import argparse
import hashlib
import json
import urllib.request

here = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output", type=Path, default=here / "build/goldens")
args = parser.parse_args()
manifest = json.loads((here / "model.json").read_text())
args.output.mkdir(parents=True, exist_ok=True)


def valid(path, file):
    if not path.exists() or path.stat().st_size != file["size"]:
        return False
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest() == file["sha256"]


for file in manifest["goldens"]:
    name = file["rfilename"]
    target = args.output / name
    if valid(target, file):
        continue
    temporary = target.with_name(target.name + ".partial")
    url = f"https://huggingface.co/{manifest['repository']}/resolve/{manifest['revision']}/{name}"
    print("fetching", name, flush=True)
    urllib.request.urlretrieve(url, temporary)
    if not valid(temporary, file):
        temporary.unlink(missing_ok=True)
        raise SystemExit(f"hash mismatch: {name}")
    temporary.replace(target)
print(args.output)
