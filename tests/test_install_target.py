"""Exercise the install wrapper with mocked tools: never signs or contacts a phone."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class InstallTargetTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "scripts").mkdir()
        (self.root / "bin").mkdir()
        shutil.copy(ROOT / "scripts/install.sh", self.root / "scripts/install.sh")
        # A wildcard profile leaves the bundle ID unchanged in these argument-only tests.
        self.tool("security", "#!/bin/sh\nprintf '<plist/>'\n")
        self.tool("plutil", "#!/bin/sh\nprintf 'TEAM.*'\n")
        self.tool("zsign", "#!/bin/sh\nexit 0\n")
        self.tool("ideviceinstaller", "#!/usr/bin/env python3\nimport json,os,sys\nopen(os.environ['ARG_LOG'],'w').write(json.dumps(sys.argv[1:]))\nsys.exit(int(os.environ.get('INSTALL_EXIT','0')))\n")
        self.env = dict(os.environ, PATH=str(self.root / "bin") + ":" + os.environ["PATH"],
                        SIGN_P12="test.p12", SIGN_PROFILE="test.mobileprovision",
                        SIGN_P12_PASSWORD="test-only", ARG_LOG=str(self.root / "args.json"))
        for key in ("DEVICE_UDID", "WIFI", "INSTALL_EXIT"):
            self.env.pop(key, None)

    def tool(self, name, contents):
        p = self.root / "bin" / name
        p.write_text(contents)
        p.chmod(0o755)

    def run_install(self, **variables):
        result = subprocess.run(["/bin/bash", str(self.root / "scripts/install.sh"), "out/app.ipa"],
                                env=dict(self.env, **variables), capture_output=True, text=True)
        args = json.loads((self.root / "args.json").read_text())
        return result, args

    def test_explicit_device(self):
        result, args = self.run_install(DEVICE_UDID="duo-udid")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(args, ["-u", "duo-udid", "install", "out/app-signed.ipa"])

    def test_device_and_wifi(self):
        result, args = self.run_install(DEVICE_UDID="duo-udid", WIFI="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(args, ["-n", "-u", "duo-udid", "install", "out/app-signed.ipa"])

    def test_legacy_unspecified_device(self):
        result, args = self.run_install()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(args, ["install", "out/app-signed.ipa"])

    def test_install_failure_remains_failure(self):
        result, _ = self.run_install(DEVICE_UDID="duo-udid", INSTALL_EXIT="7")
        self.assertEqual(result.returncode, 7)


if __name__ == "__main__":
    unittest.main()
