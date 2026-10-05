#!/usr/bin/env python3
"""Keep Spotify's Bonjour declarations when adding the mod's service types, and its own motion usage text if it has one."""

import plistlib
import sys


with open(sys.argv[1], "rb") as source, open(sys.argv[2], "rb") as additions:
    original = plistlib.load(source)
    overlay = plistlib.load(additions)

services = original.get("NSBonjourServices", [])
if not isinstance(services, list):
    raise ValueError("Spotify's NSBonjourServices is not an array")
overlay["NSBonjourServices"] = list(dict.fromkeys(services + overlay["NSBonjourServices"]))
if not original.get("NSLocalNetworkUsageDescription"):
    overlay["NSLocalNetworkUsageDescription"] = "Find nearby speakers and devices for Spotify Connect and Cast."

# The head gestures need a motion usage text; Spotify's own, if it has one, stays.
if original.get("NSMotionUsageDescription"):
    overlay.pop("NSMotionUsageDescription", None)

with open(sys.argv[3], "wb") as output:
    plistlib.dump(overlay, output)
