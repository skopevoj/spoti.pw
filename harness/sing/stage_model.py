#!/usr/bin/env python3
"""Stage Sing's compiled voice model for its host and print the manifest the app pins; uploads nothing.

The folder it makes is the model repository's contents (https://huggingface.co/Darkkos/spoti-sing): the
files of separator.mlmodelc at their paths inside it, NOTICE, and a model card. The manifest is printed the
way tweak/Sources/Shared/Sing/SGSingModel.m pins it, and compared with the table there.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

HOST = "https://huggingface.co/Darkkos/spoti-sing"
here = Path(__file__).resolve().parent
code = here.parent.parent / "tweak/Sources/Shared/Sing/SGSingModel.m"

parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument("model", type=Path, help="the compiled separator.mlmodelc (export_coreml.py makes it)")
parser.add_argument("output", type=Path, help="a new folder, to upload as the repository's contents")
args = parser.parse_args()
source, output = args.model.resolve(), args.output.resolve()
if source.suffix != ".mlmodelc" or not source.is_dir():
    parser.error("need a compiled .mlmodelc")
if output.exists():
    parser.error(f"{output} already exists")
metadata = json.loads((source / "metadata.json").read_text())
if not isinstance(metadata, list) or len(metadata) != 1 or metadata[0].get("license") != "MIT":
    parser.error("the model must keep its MIT metadata")

files = []
for path in source.rglob("*"):
    if path.is_symlink():
        parser.error(f"{path} is a link; the model's files must be regular files")
    if path.is_file():
        with path.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        files.append((path.relative_to(source).as_posix(), path.stat().st_size, digest))
files.sort(key=lambda file: (-file[1], file[0]))   # the largest first, as the app starts them

manifest = json.loads((here / "model.json").read_text())
card = f"""---
license: mit
library_name: coreml
tags:
- audio
- source-separation
- vocals
- coreml
---

# spoti.pw Sing voice model

The vocal separator [spoti.pw](https://spoti.pw)'s Sing runs on the iPhone to turn a song's vocals down
while it plays. It is Mel-Band RoFormer with KimberleyJensen's vocal checkpoint, its spectral core
exported for Core ML with two-second windows: a float32 `spectrum` of shape `[1, 2050, 201, 2]` in, the
`vocals_spectrum` of the same shape out, the STFT around it done by the app. Normalization, attention,
softmax and matrix products are float32, the rest float16. The files are a compiled `separator.mlmodelc`
as they are: the app downloads each one and keeps it only if its size and SHA-256 are the ones it pins.
It needs iOS 27, and no audio leaves the phone.

| File | Bytes | SHA-256 |
| --- | ---: | --- |
""" + "".join(f"| `{name}` | {size} | `{digest}` |\n" for name, size, digest in files) + f"""
## Provenance

* Checkpoint: [KimberleyJSN/melbandroformer](https://huggingface.co/KimberleyJSN/melbandroformer/tree/{manifest['checkpointRevision']}), MIT.
* Conversion: [john-rocky/coreai-model-zoo](https://github.com/john-rocky/coreai-model-zoo/tree/{manifest['conversionRevision']}/conversion/melband_roformer).
* Reference implementation: Mel-Band-Roformer-Vocal-Model at revision `{manifest['referenceRevision']}`.
* Exported by `harness/sing/export_coreml.py` in the spoti.pw repository.

Mel-Band RoFormer by Ju-Chiang Wang, Wei-Tsung Lu and Minz Won; the vocal checkpoint by KimberleyJensen;
lucidrains' BS-RoFormer implementation; ZFTurbo's training code. The MIT notices are in `NOTICE`.
"""

output.mkdir(parents=True)
try:
    for name, _, _ in files:
        target = output / name
        target.parent.mkdir(parents=True, exist_ok=True)
        # clonefile keeps the half a gigabyte of weights from being copied on APFS.
        if sys.platform == "darwin":
            subprocess.run(["cp", "-c", str(source / name), str(target)], check=True)
        else:
            shutil.copyfile(source / name, target)
    shutil.copyfile(here / "NOTICE", output / "NOTICE")
    (output / "README.md").write_text(card)
except BaseException:
    shutil.rmtree(output)
    raise

print(f"Staged {len(files)} model files, NOTICE and README.md in {output}")
print(f"Upload the folder's contents to {HOST} (the app reads {HOST}/resolve/main/<path>).")
print(f"Model: {sum(size for _, size, _ in files)} bytes\n")
table = [f'    {{"{name}", {size}, "{digest}"}},' for name, size, digest in files]
print("\n".join(table))
pinned = re.findall(r'\{"([^"]+)", (\d+), "([0-9a-f]{64})"\}', code.read_text())
if [(name, int(size), digest) for name, size, digest in pinned] == files:
    print(f"\nThis is the manifest {code.name} pins.")
else:
    print(f"\n{code.name} pins another manifest: replace its table with the one above before shipping this model.")
    sys.exit(1)
