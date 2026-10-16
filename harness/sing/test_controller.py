#!/usr/bin/env python3
"""Run the production lifecycle at deterministic boundaries on an already booted iOS 27 simulator."""
import argparse
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("simulator")
args = parser.parse_args()
here = Path(__file__).resolve().parent
src = here.parent.parent / "tweak/Sources"
out = here / "build/controller-test"
out.parent.mkdir(exist_ok=True)
command = ["xcrun", "--sdk", "iphonesimulator", "clang", "-target", "arm64-apple-ios27.0-simulator",
           "-fobjc-arc", "-g", "-O1", "-Wall", "-Werror", "-Wno-deprecated-declarations", "-I", str(src),
           str(here / "controller_test.m")]
command += [str(src / "Shared/Sing" / name) for name in
            ["SGSingAudio.m", "SGSingStream.m", "SGSingTimeline.m", "SGSingDSP.m"]]
command += [str(src / "Shared/Audio/SGAudioRingBuffer.m")]
for framework in ["Foundation", "UIKit", "QuartzCore", "AVFoundation", "MediaPlayer", "AudioToolbox"]:
    command += ["-framework", framework]
subprocess.run(command + ["-o", str(out)], check=True)
subprocess.run(["codesign", "-f", "-s", "-", str(out)], check=True)
subprocess.run(["xcrun", "simctl", "spawn", args.simulator, str(out)], check=True)
