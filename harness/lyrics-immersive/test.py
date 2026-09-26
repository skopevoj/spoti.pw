#!/usr/bin/env python3
"""Run the real inactivity policy on macOS/Linux without UIKit or a simulator."""
import os
from pathlib import Path
import subprocess

here = Path(__file__).resolve().parent
root = here.parent.parent
src = root / "tweak/Sources/Redesigned/Lyrics"
out = here / "build"
out.mkdir(exist_ok=True)
subprocess.run([os.environ.get("CC", "clang"), "-x", "c", "-std=c11", "-Wall", "-Wextra",
                "-Werror", "-fsanitize=address,undefined", "-g", "-I", str(src),
                str(here / "state_test.c"), str(src / "SGRImmersiveState.m"),
                "-o", str(out / "state-test")], check=True)
subprocess.run([str(out / "state-test")], check=True)
