#!/usr/bin/env python3
"""Register Sing's task in a local app/IPA before signing; never adds signing entitlements."""
import argparse
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import zipfile


def configure(info, bundle_id=None, backend="CoreAI"):
    if backend in ("CoreMLCPU", "CoreMLAdaptive"):
        return info  # Spotify's existing audio background mode owns CPU playback.
    if backend != "CoreAI":
        raise ValueError("unsupported Sing backend")
    old = info["CFBundleIdentifier"] + ".sing.*"
    identifier = (bundle_id or info["CFBundleIdentifier"]) + ".sing.*"
    permitted = [value for value in info.get("BGTaskSchedulerPermittedIdentifiers", []) if value != old]
    if identifier not in permitted:
        permitted.append(identifier)
    info["BGTaskSchedulerPermittedIdentifiers"] = permitted
    modes = info.setdefault("UIBackgroundModes", [])
    if "processing" not in modes:
        modes.append("processing")
    return info


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path, help="an unsigned .app directory or IPA")
    parser.add_argument("--bundle-id", help="the bundle identifier that the signer will use")
    args = parser.parse_args()
    app = args.app.resolve()
    if args.bundle_id and not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", args.bundle_id):
        parser.error("bundle identifier must be explicit, not a wildcard")
    if app.is_dir():
        if not (app / "Sing.bundle/Sing.plist").is_file():
            return
        backend = plistlib.loads((app / "Sing.bundle/Sing.plist").read_bytes()).get("Backend", "CoreAI")
        path = app / "Info.plist"
        info = configure(plistlib.loads(path.read_bytes()), args.bundle_id, backend)
        path.write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_BINARY))
    else:
        with zipfile.ZipFile(app) as archive:
            members = [name for name in archive.namelist() if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", name)]
            if len(members) != 1:
                parser.error("IPA must contain exactly one main app")
            member = members[0]
            manifest = member.removesuffix("Info.plist") + "Sing.bundle/Sing.plist"
            if manifest not in archive.namelist():
                return
            backend = plistlib.loads(archive.read(manifest)).get("Backend", "CoreAI")
            info = configure(plistlib.loads(archive.read(member)), args.bundle_id, backend)
        # Update only the plist, using the same zip replacement workflow as merge-appintents.py.
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / member
            path.parent.mkdir(parents=True)
            path.write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_BINARY))
            subprocess.run(["zip", "-q", str(app), member], cwd=temporary, check=True)
    if backend in ("CoreMLCPU", "CoreMLAdaptive"):
        print("    Sing Core ML uses CPU inference with Spotify's existing audio background mode")
    else:
        print("    Sing background task registered; Background GPU Access still requires an authorized signing profile")


if __name__ == "__main__":
    main()
