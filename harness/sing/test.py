#!/usr/bin/env python3
"""Portable production primitives, with ASan/UBSan (or TSAN=1 for the SPSC race test)."""
import os
from pathlib import Path
import subprocess

here = Path(__file__).resolve().parent
src = here.parent.parent / "tweak/Sources"
out = here / "build"
out.mkdir(exist_ok=True)
sanitizer = "thread" if os.environ.get("TSAN") == "1" else "address,undefined"
subprocess.run([os.environ.get("CC", "clang"), "-x", "c", "-std=c11", "-Wall", "-Wextra",
                "-Werror", "-pthread", "-fsanitize=" + sanitizer, "-g", "-I", str(src),
                str(here / "dsp_test.c"), str(src / "Shared/Audio/SGAudioRingBuffer.m"),
                str(src / "Shared/Sing/SGSingDSP.m"), "-o", str(out / "dsp-test")], check=True)
subprocess.run([str(out / "dsp-test")], check=True)
subprocess.run([os.environ.get("CC", "clang"), "-x", "c", "-std=c11", "-Wall", "-Wextra",
                "-Werror", "-pthread", "-fsanitize=" + sanitizer, "-g", "-I", str(src),
                str(here / "timeline_test.c"), str(src / "Shared/Audio/SGAudioRingBuffer.m"),
                str(src / "Shared/Sing/SGSingDSP.m"), str(src / "Shared/Sing/SGSingTimeline.m"),
                "-o", str(out / "timeline-test")], check=True)
subprocess.run([str(out / "timeline-test")], check=True)
subprocess.run([os.environ.get("CC", "clang"), "-x", "c", "-std=c11", "-Wall", "-Wextra",
                "-Werror", "-pthread", "-fsanitize=" + sanitizer, "-g", "-I", str(src),
                str(here / "stream_test.c"), str(src / "Shared/Audio/SGAudioRingBuffer.m"),
                str(src / "Shared/Sing/SGSingDSP.m"), str(src / "Shared/Sing/SGSingTimeline.m"),
                str(src / "Shared/Sing/SGSingStream.m"), "-o", str(out / "stream-test")], check=True)
subprocess.run([str(out / "stream-test")], check=True)
