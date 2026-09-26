#!/usr/bin/env python3
"""Run the production lifecycle at deterministic boundaries on an already booted simulator."""
import argparse
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("simulator")
parser.add_argument("--background", action="store_true", help="test system background-task ownership instead of the player lifecycle")
args = parser.parse_args()
here = Path(__file__).resolve().parent
src = here.parent.parent / "tweak/Sources"
out = here / ("build/background-test" if args.background else "build/controller-test")
out.parent.mkdir(exist_ok=True)
command = ["xcrun", "--sdk", "iphonesimulator", "clang", "-target", "arm64-apple-ios27.0-simulator",
           "-fobjc-arc", "-g", "-O1", "-Wall", "-Werror", "-Wno-deprecated-declarations", "-I", str(src),
           str(here / ("background_test.m" if args.background else "controller_test.m"))]
if not args.background:
    command += [str(src / "Shared/Sing" / name) for name in
                ["SGSingAudio.m", "SGSingStream.m", "SGSingTimeline.m", "SGSingDSP.m"]]
    command += [str(src / "Shared/Audio/SGAudioRingBuffer.m")]
for framework in ["Foundation", "UIKit", "QuartzCore", "AVFoundation", "MediaPlayer", "AudioToolbox", "BackgroundTasks"]:
    command += ["-framework", framework]
subprocess.run(command + ["-o", str(out)], check=True)
subprocess.run(["codesign", "-f", "-s", "-", str(out)], check=True)
subprocess.run(["xcrun", "simctl", "spawn", args.simulator, str(out)], check=True)
