#!/usr/bin/env python3
"""Fetch only pinned public model/test assets, verifying every Git/LFS object. No audio uploads."""
from pathlib import Path
import argparse
import hashlib
import json
import urllib.request

here = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument("--platform", choices=["macos", "ios"], default="macos")
parser.add_argument("--output", type=Path, default=here / "build/assets")
args = parser.parse_args()
manifest = json.loads((here / "model.json").read_text())
root = args.output
prefix = "mbr_full_fp16.aimodel/" if args.platform == "macos" else "mbr_full_fp16.h18p.aimodelc/"
for file in manifest["files"]:
    name = file["rfilename"]
    if "/" in name and not name.startswith(prefix):
        continue
    target = root / name
    target.parent.mkdir(parents=True, exist_ok=True)
    def valid(path):
        if not path.exists() or path.stat().st_size != file["size"]:
            return False
        digest = hashlib.sha256() if "lfs" in file else hashlib.sha1()
        if "lfs" not in file:
            digest.update(f"blob {file['size']}\0".encode())
        with path.open("rb") as stream:
            for part in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(part)
        return digest.hexdigest() == (file["lfs"]["sha256"] if "lfs" in file else file["blobId"])
    if valid(target):
        continue
    temporary = target.with_name(target.name + ".partial")
    url = f"https://huggingface.co/{manifest['repository']}/resolve/{manifest['revision']}/{name}"
    print("fetching", name, flush=True)
    urllib.request.urlretrieve(url, temporary)
    if not valid(temporary):
        temporary.unlink(missing_ok=True)
        raise SystemExit(f"hash mismatch: {name}")
    temporary.replace(target)
print(root)
