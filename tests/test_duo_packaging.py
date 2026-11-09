import importlib.util
from pathlib import Path
import plistlib
import shutil
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location('duo', Path(__file__).resolve().parents[1] / 'scripts/retarget-duo.py')
duo = importlib.util.module_from_spec(spec)
spec.loader.exec_module(duo)


class DuoValidationTests(unittest.TestCase):
    def test_versions_and_sdk_floor(self):
        for invalid in ('27.x', '27.1.1.1', '-27', '27.256', '²7.1'):
            with self.assertRaises(ValueError):
                duo.packed_version(invalid)
        with patch.object(duo, 'run', return_value='27.0'):
            with self.assertRaisesRegex(ValueError, '27.1'):
                duo.installed_sdk()

    def test_malformed_binary(self):
        for data in (b'', b'not a binary', struct.pack('<8I', 0xfeedfacf, 0x100000c, 0, 2, 1, 24, 0, 0)):
            with self.assertRaises(ValueError):
                duo.build_version(data)

    def test_failed_retarget_preserves_archive(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'app.ipa'
            with zipfile.ZipFile(path, 'w') as z:
                z.writestr('Payload/App.app/Info.plist', plistlib.dumps({'CFBundleExecutable': 'Main'}))
                z.writestr('Payload/App.app/Main', b'invalid Mach-O')
            original = path.read_bytes()
            with self.assertRaises(ValueError):
                duo.retarget_archive(path, '27.2', 'test')
            self.assertEqual(path.read_bytes(), original)

    def test_archive_selection(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'app.ipa'
            with zipfile.ZipFile(path, 'w') as z:
                z.writestr('Payload/Renamed.app/Info.plist', plistlib.dumps({'CFBundleExecutable': 'ActualExecutable'}))
                z.writestr('Payload/Renamed.app/ActualExecutable', b'fixture')
                z.writestr('Payload/Renamed.app/PlugIns/Widget.appex/Info.plist', b'ignored')
            with zipfile.ZipFile(path) as z:
                self.assertEqual(duo.select_app(z)[1], 'Payload/Renamed.app/ActualExecutable')
            with zipfile.ZipFile(path, 'a') as z:
                z.writestr('Payload/Other.app/Info.plist', plistlib.dumps({'CFBundleExecutable': 'Other'}))
            with zipfile.ZipFile(path) as z:
                with self.assertRaises(ValueError):
                    duo.select_app(z)


@unittest.skipUnless(shutil.which('xcrun') and shutil.which('ldid'), 'requires Xcode and ldid')
class DuoRealMachOTests(unittest.TestCase):
    def test_real_binary_and_archive(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source, binary = root / 'main.c', root / 'Main'
            source.write_text('int main(void) { return 0; }\n')
            sdk = duo.run('xcrun', '--sdk', 'iphoneos', '--show-sdk-path')
            subprocess.run(['xcrun', '--sdk', 'iphoneos', 'clang', '-target', 'arm64-apple-ios16.1',
                            '-isysroot', sdk, '-Wl,-rpath,@executable_path/Frameworks',
                            str(source), '-o', str(binary)], check=True)
            subprocess.run(['xcrun', 'vtool', '-set-build-version', 'ios', '16.1', '27.0',
                            '-tool', 'ld', '27037.1', '-replace', '-output', str(root / 'old'), str(binary)], check=True)
            (root / 'old').replace(binary)
            ents = root / 'ents.plist'
            ents.write_bytes(plistlib.dumps({'get-task-allow': True}))
            subprocess.run(['ldid', '-S' + str(ents), str(binary)], check=True)
            before = binary.read_bytes()
            old_commands = [(cmd, raw) for cmd, raw in duo.commands(before) if cmd in (0xc, 0x8000001c)]
            self.assertTrue(old_commands)  # Real LC_LOAD_DYLIB and LC_RPATH survive.
            self.assertTrue(duo.retarget_binary(binary, '27.2'))
            minimum, sdk, tools = duo.build_version(binary.read_bytes())
            self.assertEqual((minimum, sdk, tools), (duo.packed_version('16.1'), duo.packed_version('27.2'),
                                                    [(3, duo.packed_version('27037.1'))]))
            self.assertEqual(old_commands, [(cmd, raw) for cmd, raw in duo.commands(binary.read_bytes())
                                            if cmd in (0xc, 0x8000001c)])
            self.assertEqual(plistlib.loads(duo.run('ldid', '-e', str(binary)).encode()), {'get-task-allow': True})
            stable = binary.read_bytes()
            self.assertFalse(duo.retarget_binary(binary, '27.2'))
            self.assertEqual(stable, binary.read_bytes())
            with self.assertRaises(ValueError):
                duo.retarget_binary(binary, '27.0')
            with self.assertRaises(ValueError):
                duo.retarget_binary(binary, '27.1')
            path = root / 'app.ipa'
            with zipfile.ZipFile(path, 'w') as z:
                z.writestr('Payload/Different.app/Info.plist', plistlib.dumps({'CFBundleExecutable': 'Main', 'MinimumOSVersion': '16.1'}))
                z.writestr('Payload/Different.app/Main', before)
                z.writestr('Payload/Different.app/Frameworks/injected.dylib', b'unmodified dylib')
            self.assertTrue(duo.retarget_archive(path, '27.2', 'fixture-build'))
            with zipfile.ZipFile(path) as z:
                info = plistlib.loads(z.read('Payload/Different.app/Info.plist'))
                self.assertEqual(info['MinimumOSVersion'], '16.1')
                self.assertEqual(info['DTSDKName'], 'iphoneos27.2')
                self.assertEqual(info['DTSDKBuild'], 'fixture-build')
                self.assertEqual(z.read('Payload/Different.app/Frameworks/injected.dylib'), b'unmodified dylib')
            stable = path.read_bytes()
            self.assertFalse(duo.retarget_archive(path, '27.2', 'fixture-build'))
            self.assertEqual(stable, path.read_bytes())
