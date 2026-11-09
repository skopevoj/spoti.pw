#!/usr/bin/env python3
"""Opt a packaged app into Duo sizing using the selected iPhoneOS SDK (27.1+).

Only the main executable is retargeted. This is metadata retargeting, not a
recompilation or a promise that upstream code supports every new SDK behavior.
"""
import argparse
import importlib.util
import os
from pathlib import Path
import plistlib
import struct
import subprocess
import sys
import tempfile
import zipfile

_spec = importlib.util.spec_from_file_location('ipa_preflight', Path(__file__).with_name('validate-ipa.py'))
preflight = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(preflight)


def packed_version(value):
    parts = value.split('.')
    if not 1 <= len(parts) <= 3 or any(not p.isascii() or not p.isdecimal() for p in parts):
        raise ValueError(f'invalid SDK version: {value!r}')
    parts = [int(p) for p in parts] + [0] * (3 - len(parts))
    if parts[0] > 65535 or any(p > 255 for p in parts[1:]):
        raise ValueError('version component out of range')
    return (parts[0] << 16) | (parts[1] << 8) | parts[2]


def version_string(value):
    return f'{value >> 16}.{(value >> 8) & 255}.{value & 255}'


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def installed_sdk():
    version = run('xcrun', '--sdk', 'iphoneos', '--show-sdk-version')
    if packed_version(version) < packed_version('27.1'):
        raise ValueError('Duo builds need the selected Xcode iPhoneOS SDK 27.1 or newer')
    build = run('xcrun', '--sdk', 'iphoneos', '--show-sdk-build-version')
    if not build:
        raise ValueError('selected iPhoneOS SDK has no build identifier')
    return version, build


def commands(data):
    preflight.validate_binary(data)
    offset = 32
    result = []
    for _ in range(struct.unpack_from('<I', data, 16)[0]):
        cmd, size = struct.unpack_from('<II', data, offset)
        result.append((cmd, data[offset:offset + size]))
        offset += size
    return result


def build_version(data):
    builds = [raw for cmd, raw in commands(data) if cmd == 0x32]
    if len(builds) != 1:
        raise ValueError('main executable must have exactly one LC_BUILD_VERSION')
    raw = builds[0]
    if len(raw) < 24:
        raise ValueError('truncated LC_BUILD_VERSION')
    _, size, platform, minimum, sdk, ntools = struct.unpack_from('<6I', raw)
    if platform != 2 or size != 24 + ntools * 8:
        raise ValueError('invalid or non-iOS LC_BUILD_VERSION')
    return minimum, sdk, [struct.unpack_from('<II', raw, 24 + i * 8) for i in range(ntools)]


def select_app(archive):
    names = archive.namelist()
    infos = [n for n in names if n.startswith('Payload/') and n.count('/') == 2
             and n.endswith('.app/Info.plist')]
    if len(infos) != 1 or len(names) != len(set(names)):
        raise ValueError('IPA must have one top-level app and no duplicate ZIP entries')
    info = plistlib.loads(archive.read(infos[0]))
    executable = info.get('CFBundleExecutable')
    if (not isinstance(executable, str) or not executable or '/' in executable
            or '\\' in executable or executable in ('.', '..')):
        raise ValueError('invalid CFBundleExecutable')
    binary = infos[0].rsplit('/', 1)[0] + '/' + executable
    archive.getinfo(binary)
    return infos[0], binary, info


def retarget_binary(path, sdk):
    target = packed_version(sdk)
    if target < packed_version('27.1'):
        raise ValueError('Duo requires SDK 27.1 or newer')
    original = path.read_bytes()
    minimum, current, tools = build_version(original)
    if current > target:
        raise ValueError('selected SDK is older than the main executable; refusing to downgrade')
    if current == target:
        return False
    entitlements = run('ldid', '-e', str(path))
    # Validate before changing anything. Empty output is valid for an unentitled app.
    if entitlements:
        plistlib.loads(entitlements.encode())
    output = path.with_name(path.name + '.retargeted')
    args = ['xcrun', 'vtool', '-set-build-version', 'ios', version_string(minimum), sdk]
    for tool, version in tools:
        args += ['-tool', str(tool), version_string(version)]
    subprocess.run(args + ['-replace', '-output', str(output), str(path)], check=True)
    modified = output.read_bytes()
    if build_version(modified) != (minimum, target, tools):
        raise ValueError('vtool failed to preserve deployment target/build tools')
    # Includes injected dylib loads, rpaths, encryption status, segments and signature command.
    other = lambda data: [raw for cmd, raw in commands(data) if cmd != 0x32]
    if other(original) != other(modified):
        raise ValueError('vtool unexpectedly changed another load command')
    ents = path.with_name(path.name + '.entitlements.plist')
    if entitlements:
        ents.write_text(entitlements)
    subprocess.run(['ldid', '-S' + (str(ents) if entitlements else ''), str(output)], check=True)
    if build_version(output.read_bytes()) != (minimum, target, tools):
        raise ValueError('signing unexpectedly changed build metadata')
    output.replace(path)
    return True


def retarget_archive(path, sdk, sdk_build):
    path = Path(path).resolve()
    # A complete replacement is prepared next to the IPA, then atomically published.
    # Failure never leaves a partly modified archive. No archive paths are extracted.
    with tempfile.TemporaryDirectory(prefix='.duo-', dir=path.parent) as temporary:
        directory = Path(temporary)
        replacement = directory / 'output.ipa'
        with zipfile.ZipFile(path) as source:
            plist_name, binary_name, info = select_app(source)
            binary = directory / 'main'
            binary.write_bytes(source.read(binary_name))
            binary.chmod(0o755)
            changed = retarget_binary(binary, sdk)
            updated = dict(info, DTSDKName=f'iphoneos{sdk}', DTPlatformVersion=sdk,
                           DTSDKBuild=sdk_build, DTPlatformBuild=sdk_build)
            if not changed and updated == info:
                return False
            with zipfile.ZipFile(replacement, 'w') as destination:
                destination.comment = source.comment
                for entry in source.infolist():
                    if entry.filename == binary_name:
                        destination.writestr(entry, binary.read_bytes())
                    elif entry.filename == plist_name:
                        destination.writestr(entry, plistlib.dumps(updated, fmt=plistlib.FMT_BINARY))
                    else:
                        with source.open(entry) as src, destination.open(entry, 'w') as dst:
                            import shutil
                            shutil.copyfileobj(src, dst)
        replacement.chmod(path.stat().st_mode & 0o777)
        os.replace(replacement, path)
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ipa', nargs='?')
    parser.add_argument('--check-sdk', action='store_true')
    args = parser.parse_args()
    try:
        sdk, build = installed_sdk()
        if not args.check_sdk:
            if not args.ipa:
                parser.error('IPA required unless --check-sdk is used')
            changed = retarget_archive(args.ipa, sdk, build)
            print(f'Duo: main executable SDK {sdk} ({"retargeted" if changed else "already configured"})')
        else:
            print(f'Duo: selected iPhoneOS SDK {sdk} ({build})')
    except (OSError, ValueError, KeyError, zipfile.BadZipFile, plistlib.InvalidFileException,
            subprocess.CalledProcessError) as error:
        print(f'Duo packaging: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
