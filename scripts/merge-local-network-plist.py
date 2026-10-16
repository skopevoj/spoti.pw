#!/usr/bin/env python3
"""Keep Spotify's Bonjour declarations when adding the mod's service types, and word the permissions the
mod asks for that Spotify never does."""

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

# AirPods head tracking (Shared/HeadMotion), for Spatial voice and AirPods gestures.
if not original.get("NSMotionUsageDescription"):
    overlay["NSMotionUsageDescription"] = "Follow your head with AirPods for Spatial voice and AirPods gestures."

# A build made with the plist part left out (SG_DISABLE, Core/SGPrefs.h) adds neither of the two keys below.
import os
if "plist" in os.environ.get("SG_DISABLE", "").split(","):
    overlay.pop("MusicHapticsSupported", None)
    overlay.pop("NSMotionUsageDescription", None)

with open(sys.argv[3], "wb") as output:
    plistlib.dump(overlay, output)
