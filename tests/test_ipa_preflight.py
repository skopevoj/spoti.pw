import importlib.util
import plistlib
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("preflight", ROOT / "scripts/validate-ipa.py")
preflight = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preflight)


def binary(cryptid=0, cpu=preflight.CPU_TYPE_ARM64):
    return struct.pack("<8I", 0xFEEDFACF, cpu, 0, 2, 1, 24, 0, 0) + struct.pack("<6I", 0x2C, 24, 0, 0, cryptid, 0)


class IPAPreflightTests(unittest.TestCase):
    def ipa(self, version="9.1.78", bundle="com.spotify.client", image=None):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        path = Path(temp.name) / "Spotify.ipa"
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr("Payload/Spotify.app/Info.plist", plistlib.dumps({
                "CFBundleIdentifier": bundle, "CFBundleExecutable": "Spotify",
                "CFBundleShortVersionString": version,
            }))
            archive.writestr("Payload/Spotify.app/Spotify", binary() if image is None else image)
        return path

    def test_supported_decrypted_ipa(self):
        self.assertEqual(preflight.validate(self.ipa()), "9.1.78")

    def test_old_spotify_rejected(self):
        with self.assertRaisesRegex(ValueError, "requires 9.1.78"):
            preflight.validate(self.ipa(version="9.1.36"))

    def test_explicitly_selected_candidate_version(self):
        self.assertEqual(preflight.validate(self.ipa(version="9.1.94"), "9.1.94"), "9.1.94")

    def test_other_app_rejected(self):
        with self.assertRaisesRegex(ValueError, "original com.spotify.client"):
            preflight.validate(self.ipa(bundle="com.example.other"))

    def test_encrypted_ipa_rejected(self):
        with self.assertRaisesRegex(ValueError, "encrypted"):
            preflight.validate(self.ipa(image=binary(cryptid=1)))

    def test_other_architecture_rejected(self):
        with self.assertRaisesRegex(ValueError, "arm64"):
            preflight.validate_binary(binary(cpu=0x01000007))

    def test_universal_arm64_rejected_until_extractor_supports_it(self):
        arm = binary()
        fat = struct.pack(">2I5I", 0xCAFEBABE, 1, preflight.CPU_TYPE_ARM64, 0, 28, len(arm), 0) + arm
        with self.assertRaisesRegex(ValueError, "universal"):
            preflight.validate_binary(fat)

    def test_truncated_load_commands(self):
        with self.assertRaisesRegex(ValueError, "truncated"):
            preflight.validate_binary(binary()[:-1])

    def test_invalid_command_length(self):
        damaged = bytearray(binary())
        struct.pack_into("<I", damaged, 36, 0)
        with self.assertRaisesRegex(ValueError, "command size"):
            preflight.validate_binary(damaged)

    def test_wrong_command_count(self):
        damaged = bytearray(binary())
        struct.pack_into("<I", damaged, 16, 0)
        with self.assertRaisesRegex(ValueError, "count"):
            preflight.validate_binary(damaged)


if __name__ == "__main__":
    unittest.main()
