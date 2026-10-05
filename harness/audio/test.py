#!/usr/bin/env python3
"""Exercise the pipeline's Core Audio boundary on macOS; no simulator or device required."""
import os
from pathlib import Path
import subprocess
import tempfile

here = Path(__file__).resolve().parent
src = here.parent.parent / "tweak/Sources"
sanitizer = "thread" if os.environ.get("TSAN") else "address,undefined"
with tempfile.TemporaryDirectory(prefix="spoti-audio-") as directory:
    output = Path(directory) / "test"
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-g", "-O1", "-Wall", "-Werror",
                    "-Wno-deprecated-declarations", f"-fsanitize={sanitizer}", "-I", str(src),
                    str(here / "main.m"), str(src / "Shared/Sing/SGSingAudio.m"),
                    str(src / "Shared/Sing/SGSingStream.m"), str(src / "Shared/Sing/SGSingTimeline.m"),
                    str(src / "Shared/Sing/SGSingDSP.m"), str(src / "Shared/Audio/SGAudioRingBuffer.m"),
                    "-framework", "Foundation", "-framework", "AudioToolbox",
                    "-o", str(output)], check=True)
    subprocess.run([str(output)], check=True)
    queue = Path(directory) / "source-queue-test"
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-g", "-O1", "-Wall", "-Werror",
                    f"-fsanitize={sanitizer}", "-I", str(src), str(here / "source_queue_test.m"),
                    "-framework", "Foundation", "-framework", "AudioToolbox", "-o", str(queue)], check=True)
    subprocess.run([str(queue)], check=True)
