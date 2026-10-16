#!/usr/bin/env python3
"""Adds the actions of a Metadata.appintents to the app's own inside an IPA, in place.

  scripts/merge-appintents.py <ipa> <Payload/X.app/> <Metadata.appintents dir>

The system looks an intent up in the metadata of the bundle that runs it, and a LiveActivityIntent
runs in the app, so the widget's intents have to be listed in Spotify's file next to its own. So are the
speed and pitch presets' (Shared/Player/SpeedPitchIntents.swift): their actions, the entity and its
query, and the App Shortcuts Siri answers to. An app has one set of App Shortcuts, so if Spotify's own
file already has some, ours are left out (the intents are still in Shortcuts' list of actions).
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile

ipa, app_dir, ours = sys.argv[1:4]
member = f"{app_dir}Metadata.appintents/extract.actionsdata"
version = f"{app_dir}Metadata.appintents/version.json"

with zipfile.ZipFile(ipa) as z:
    theirs = json.loads(z.read(member)) if member in z.namelist() else None
with open(os.path.join(ours, "extract.actionsdata")) as f:
    added = json.load(f)

def merge(theirs, added):
    """Everything of ours added to Spotify's: maps by name, lists after theirs without repeats."""
    if theirs is None:
        return added
    merged = dict(theirs)
    for key, value in added.items():
        if key not in merged or merged[key] in (None, {}, []):
            merged[key] = value
        elif isinstance(value, dict) and isinstance(merged[key], dict):
            merged[key] = {**merged[key], **value}
        elif isinstance(value, list) and isinstance(merged[key], list):
            merged[key] = merged[key] + [item for item in value if item not in merged[key]]
        # Anything else (a version number) stays Spotify's.
    return merged


if theirs is not None and theirs.get("autoShortcuts"):
    print("    Spotify already has App Shortcuts: the speed and pitch ones are left out")
    added.pop("autoShortcuts", None)
merged = merge(theirs, added)
print("    merged keys: " + ", ".join(f"{k}={len(v) if hasattr(v, '__len__') else v}" for k, v in merged.items()))

with tempfile.TemporaryDirectory() as tmp:
    os.makedirs(os.path.join(tmp, os.path.dirname(member)))
    with open(os.path.join(tmp, member), "w") as f:
        json.dump(merged, f)
    entries = [member]
    if theirs is None:
        shutil.copy(os.path.join(ours, "version.json"), os.path.join(tmp, version))
        entries.append(version)
    subprocess.run(["zip", "-q", os.path.abspath(ipa), *entries], cwd=tmp, check=True)

print(f"    {len(added['actions'])} actions added to {len(merged['actions']) - len(added['actions'])} of the app's")
for key in ("autoShortcuts", "entities", "queries"):
    if key in added:
        print(f"    {key}: {json.dumps(added[key])[:1500]}")
