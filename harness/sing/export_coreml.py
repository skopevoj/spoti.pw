#!/usr/bin/env python3
"""Export the pinned two-second spectral separator for CPU-only Core ML; no downloads."""
import argparse
import hashlib
from importlib.metadata import version
import json
from pathlib import Path
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("conversion", type=Path, help="pinned coreai-model-zoo checkout")
parser.add_argument("reference", type=Path, help="pinned Mel-Band-Roformer-Vocal-Model checkout")
parser.add_argument("checkpoint", type=Path)
parser.add_argument("golden_raw", type=Path, help="original eight-second planar golden input")
parser.add_argument("output", type=Path, help="new local export directory")
parser.add_argument("--precision", choices=("mixed", "float32"), default="mixed",
                    help="mixed CPU profile, or the full-precision comparison model")
args = parser.parse_args()
manifest = json.loads((Path(__file__).parent / "model.json").read_text())
profile = manifest["cpuProfile"]
for package, key in [("coremltools", "coremltoolsVersion"), ("torch", "torchVersion")]:
    if version(package) != profile[key]:
        raise ValueError(f"{package} must be {profile[key]} for this export")

def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()

if digest(args.checkpoint) != manifest["checkpointSHA256"]:
    raise ValueError("checkpoint hash mismatch")
expected_raw = next(f["lfs"]["sha256"] for f in manifest["files"] if f["rfilename"] == "golden_raw.f32")
if digest(args.golden_raw) != expected_raw:
    raise ValueError("golden input hash mismatch")
for checkout, revision, paths in [
    (args.conversion, manifest["conversionRevision"], ["conversion/melband_roformer/export_core.py"]),
    (args.reference, manifest["referenceRevision"], ["models", "configs"]),
]:
    subprocess.run(["git", "-C", str(checkout), "diff", "--quiet", revision, "--", *paths], check=True)
conversion = args.conversion.resolve() / "conversion/melband_roformer"
sys.path[:0] = [str(conversion), str(args.reference.resolve())]

import coremltools as ct
import numpy as np
import torch
import torch.nn.functional as F
import yaml
import models.mel_band_roformer.attend as attention
from models.mel_band_roformer import MelBandRoformer
from export_core import SepCore, HostDSP

args.output.mkdir(parents=True, exist_ok=False)
torch.set_num_threads(2)
attention.Attend.flash_attn = lambda self, q, k, v: F.scaled_dot_product_attention(q, k, v, dropout_p=0.)
config = yaml.full_load((args.reference / "configs/config_vocals_mel_band_roformer.yaml").read_text())
model = MelBandRoformer(**config["model"]).eval()
model.load_state_dict(torch.load(args.checkpoint, map_location="cpu", weights_only=True), strict=True)
raw = np.fromfile(args.golden_raw, np.float32).reshape(2, -1)[:, :88200].copy()
host, core = HostDSP(model), SepCore(model).eval().float()
with torch.inference_mode():
    spectrum = host.stft(torch.from_numpy(raw).unsqueeze(0)).float()
    expected = core(spectrum)
    reference = host.istft(expected, length=88200)[0].numpy().copy()
    traced = torch.jit.trace(core, spectrum, check_trace=False)
    if not torch.allclose(traced(spectrum), expected, atol=1e-5, rtol=1e-4):
        raise ValueError("spectral trace changed the reference output")
    # Keep normalization and attention in FP32. Converting the denominator's tile to
    # FP16 rounds its 1e-12 floor to zero, even if maximum and division stay FP32.
    full_precision = set(profile["float32Operations"])
    precision = ct.precision.FLOAT32 if args.precision == "float32" else ct.transform.FP16ComputePrecision(
        op_selector=lambda op: op.op_type not in full_precision)
    converted = ct.convert(traced,
        inputs=[ct.TensorType(name="spectrum", shape=spectrum.shape, dtype=np.float32)],
        outputs=[ct.TensorType(name="vocals_spectrum", dtype=np.float32)],
        convert_to="mlprogram", compute_precision=precision,
        minimum_deployment_target=ct.target.iOS18, compute_units=ct.ComputeUnit.CPU_ONLY,
        skip_model_load=True)
    converted.author = "KimberleyJensen; john-rocky spectral conversion"
    converted.license = "MIT"
    converted.short_description = "Pinned Mel-Band RoFormer, 2-second spectral Core ML feasibility"
    package = args.output / "separator.mlpackage"
    converted.save(str(package))
    raw.tofile(args.output / "golden_raw.f32")
    reference.tofile(args.output / "golden_vocals.f32")
    np.ascontiguousarray(spectrum.numpy()).tofile(args.output / "spectrum.f32")
    np.ascontiguousarray(expected.numpy()).tofile(args.output / "expected-spectrum.f32")
subprocess.run(["xcrun", "coremlcompiler", "compile", str(package), str(args.output),
                "--platform", "ios", "--deployment-target", "18.0"], check=True)
compiled = args.output / "separator.mlmodelc"
hashes = {p.relative_to(compiled).as_posix(): digest(p) for p in compiled.rglob("*") if p.is_file()}
(args.output / "hashes.json").write_text(json.dumps(hashes, indent=2) + "\n")
print(f"Exported {args.precision} CPU candidate; run native parity, worker, and physical-device checks before use.")
