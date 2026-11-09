#!/usr/bin/env python3
"""Reject an unsupported or still-encrypted Spotify IPA before building the tweak."""
import argparse
import plistlib
import struct
import sys
import zipfile

SUPPORTED_VERSION = "9.1.78"
CPU_TYPE_ARM64 = 0x0100000C


def arm64_image(data):
    """Only thin ARM64 is supported by the flag extractor's address calculations."""
    if data[:4] in (b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf",
                    b"\xbe\xba\xfe\xca", b"\xbf\xba\xfe\xca"):
        raise ValueError("universal Mach-O is unsupported by the flag extractor; supply a thin arm64 IPA")
    if data[:4] != b"\xcf\xfa\xed\xfe":
        raise ValueError("Spotify executable is not a supported arm64 Mach-O")
    return data


def validate_binary(data):
    data = arm64_image(data)
    if len(data) < 32 or data[:4] != b"\xcf\xfa\xed\xfe":
        raise ValueError("truncated or unsupported arm64 Mach-O header")
    _, cpu, _, filetype, ncmds, sizeofcmds, _, _ = struct.unpack_from("<8I", data)
    if cpu != CPU_TYPE_ARM64 or filetype != 2:
        raise ValueError("Spotify executable must be an arm64 executable")
    end = 32 + sizeofcmds
    if end > len(data):
        raise ValueError("truncated Mach-O load commands")
    offset = 32
    for _ in range(ncmds):
        if offset + 8 > end:
            raise ValueError("truncated Mach-O load command")
        cmd, size = struct.unpack_from("<II", data, offset)
        if size < 8 or offset + size > end:
            raise ValueError("invalid Mach-O load command size")
        if cmd in (0x21, 0x2C):  # LC_ENCRYPTION_INFO / LC_ENCRYPTION_INFO_64
            if size < (24 if cmd == 0x2C else 20):
                raise ValueError("truncated encryption load command")
            if struct.unpack_from("<I", data, offset + 16)[0] != 0:
                raise ValueError("Spotify IPA is encrypted; supply your decrypted IPA for the selected version")
        offset += size
    if offset != end:
        raise ValueError("Mach-O load command count does not match its size")


def validate(path, expected_version=SUPPORTED_VERSION):
    with zipfile.ZipFile(path) as archive:
        infos = [name for name in archive.namelist()
                 if name.startswith("Payload/") and name.count("/") == 2
                 and name.endswith(".app/Info.plist")]
        if len(infos) != 1:
            raise ValueError("IPA must contain exactly one Payload/*.app/Info.plist")
        info = plistlib.loads(archive.read(infos[0]))
        version = info.get("CFBundleShortVersionString")
        if version != expected_version:
            raise ValueError(f"unsupported Spotify version {version!r}; this build requires {expected_version}")
        if info.get("CFBundleIdentifier") != "com.spotify.client":
            raise ValueError("source IPA is not the original com.spotify.client app")
        executable = info.get("CFBundleExecutable")
        if not isinstance(executable, str) or not executable or "/" in executable or executable in (".", ".."):
            raise ValueError("invalid CFBundleExecutable")
        validate_binary(archive.read(infos[0].rsplit("/", 1)[0] + "/" + executable))
    return version


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa")
    parser.add_argument("--expected-version", default=SUPPORTED_VERSION,
                        help="version intentionally selected for this build (default: %(default)s)")
    args = parser.parse_args()
    try:
        version = validate(args.ipa, args.expected_version)
    except (OSError, ValueError, KeyError, zipfile.BadZipFile, plistlib.InvalidFileException) as error:
        print(f"IPA preflight: {error}", file=sys.stderr)
        sys.exit(1)
    print(f"IPA preflight: decrypted Spotify {version}, arm64")
