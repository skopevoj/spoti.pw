#!/usr/bin/env python3
"""Export a fixed short window from the pinned checkpoint; compare it to PyTorch before benchmarking."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("conversion", type=Path, help="coreai-model-zoo checkout")
parser.add_argument("reference", type=Path, help="Mel-Band-Roformer-Vocal-Model checkout")
parser.add_argument("checkpoint", type=Path)
parser.add_argument("golden_raw", type=Path, help="pinned eight-second golden_raw.f32")
parser.add_argument("output", type=Path, help="new local output directory")
parser.add_argument("--seconds", type=int, choices=(2, 4), default=2)
args = parser.parse_args()
manifest = json.loads((Path(__file__).parent / "model.json").read_text())

def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()

if digest(args.checkpoint) != manifest["checkpointSHA256"]:
    raise ValueError("checkpoint hash mismatch")
raw_hash = next(f["lfs"]["sha256"] for f in manifest["files"] if f["rfilename"] == "golden_raw.f32")
if digest(args.golden_raw) != raw_hash:
    raise ValueError("golden input hash mismatch")
conversion = args.conversion.resolve() / "conversion/melband_roformer"
for checkout, revision, paths in [
    (args.conversion, manifest["conversionRevision"], ["conversion/melband_roformer"]),
    (args.reference, manifest["referenceRevision"], ["models", "configs"]),
]:
    subprocess.run(["git", "-C", str(checkout), "diff", "--quiet", revision, "--", *paths], check=True)
args.output.mkdir(parents=True, exist_ok=False)
sys.path[:0] = [str(conversion), str(args.reference.resolve())]

import numpy as np
import torch
import yaml
import torch.nn.functional as F
import models.mel_band_roformer.attend as attention
from models.mel_band_roformer import MelBandRoformer
from export_core2 import SepFull2, frame_host, overlap_add_host
import coreai_models.export.macos as exporter
import coreai.runtime as rt

torch.set_num_threads(2)
attention.Attend.flash_attn = lambda self, q, k, v: F.scaled_dot_product_attention(q, k, v, dropout_p=0.0)
exporter.EXTERNALIZE_SPECS = [s for s in exporter.EXTERNALIZE_SPECS
    if s.composite_op_name not in {"scaled_dot_product_attention", "rope"}]
config = yaml.full_load((args.reference / "configs/config_vocals_mel_band_roformer.yaml").read_text())
model = MelBandRoformer(**config["model"]).eval()
model.load_state_dict(torch.load(args.checkpoint, map_location="cpu", weights_only=True), strict=True)
samples = args.seconds * 44100
raw = np.fromfile(args.golden_raw, dtype=np.float32).reshape(2, -1)[:, :samples].copy()
print("Computing short-window reference", flush=True)
with torch.no_grad():
    reference = model(torch.from_numpy(raw).unsqueeze(0))[0].numpy().copy()
full = SepFull2(model).eval().half()
frames = torch.from_numpy(frame_host(raw, samples // 441 + 1)).half().unsqueeze(0)
with torch.no_grad():
    reconstruction = overlap_add_host(full(frames)[0].float().numpy(), samples)
dot = np.sum(reconstruction.astype(np.float64) * reference)
cosine = dot / (np.linalg.norm(reconstruction) * np.linalg.norm(reference))
if not np.isfinite(cosine) or cosine < .999:
    raise ValueError(f"short-window conversion parity failed: {cosine}")
print(f"Exporting {list(frames.shape)}, PyTorch parity {cosine:.7f}", flush=True)
program = exporter.export_to_coreai(full, {"frames": frames}, dynamic_shapes=None,
    input_names=("frames",), output_names=("recon",), state_names=None)
program.optimize()
aim = args.output / "mbr_full_fp16.aimodel"
metadata = rt.AIModelAssetMetadata()
metadata.author = "KimberleyJensen; john-rocky conversion"
metadata.license = "MIT"
metadata.model_description = f"Mel-Band RoFormer {args.seconds}s feasibility export"
program.save_asset(aim, metadata)
raw.tofile(args.output / "golden_raw.f32")
reference.astype(np.float32).tofile(args.output / "golden_vocals.f32")
hashes = {str(p.relative_to(aim)): digest(p) for p in aim.rglob("*") if p.is_file()}
(args.output / "hashes.json").write_text(json.dumps(hashes, indent=2) + "\n")
print(f"Saved {args.output}; run benchmark.swift with hashes.json, then the device and overlap tests.")
