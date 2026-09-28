#!/usr/bin/env python3
"""Run the real album hooks on a booted iOS 26+ simulator; THEOS must point to Theos."""
import argparse
from pathlib import Path
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("simulator", help="UDID of a booted simulator")
args = parser.parse_args()
here = Path(__file__).resolve().parent
subprocess.run([str(here / "build.sh")], check=True)
subprocess.run(["xcrun", "simctl", "install", args.simulator,
                str(here / "build/AlbumHarness.app")], check=True)
for mode in ("redesign", "native", "late"):
    log = here / "build" / (mode + ".log")
    command = ["xcrun", "simctl", "launch", "--terminate-running-process", "--console",
               args.simulator, "com.vojta.albumharness"]
    if mode != "redesign":
        command.append(mode)
    with log.open("w") as output:
        process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT)
        try:
            # Include late metadata and Spotify's later layout passes after the synchronous checks.
            deadline = time.monotonic() + 8
            while time.monotonic() < deadline and process.poll() is None:
                time.sleep(0.1)
            report = log.read_text()
            if process.poll() is not None or "[album-checks] PASS" not in report or "FAIL:" in report:
                raise RuntimeError(mode + " failed:\n" + report)
            print(next(line for line in report.splitlines() if "[album-checks] PASS" in line))
            if mode == "late" and 'late: Play\'s right shows "Save to Your Library"' not in report:
                raise RuntimeError("Late header control did not refresh:\n" + report)
        finally:
            subprocess.run(["xcrun", "simctl", "terminate", args.simulator,
                            "com.vojta.albumharness"], capture_output=True)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.terminate()
                process.wait(timeout=5)
