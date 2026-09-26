#!/usr/bin/env python3
"""Build the real UIKit adapter and karaoke view on an iOS 26 simulator."""
from pathlib import Path
import os
import plistlib
import shutil
import subprocess

here = Path(__file__).resolve().parent
root = here.parent.parent
src = root / "tweak/Sources"
app = here / "build/LyricsImmersive.app"
app.mkdir(parents=True, exist_ok=True)
generated = here / "build/LyricsImmersive.m"
theos = Path(os.environ.get("THEOS", Path.home() / "theos"))
with generated.open("w") as output:
    subprocess.run([str(theos / "bin/logos.pl"), "-c", "generator=internal",
                    str(src / "Redesigned/Lyrics/LyricsImmersive.x")], stdout=output, check=True)
sources = [here / "main.m", here / "sing_stubs.m", here.parent / "lyrics/stubs.m"]
sources += [generated, src / "Core/SGUIMode.m"]
sources += [src / name for name in [
    "Redesigned/Lyrics/SGRSingControl.m", "Redesigned/Kit/SGRGlass.m",
    "Redesigned/Lyrics/SGRLyricsImmersive.m", "Redesigned/Lyrics/SGRImmersiveState.m",
    "Redesigned/Lyrics/SGRKaraokeView.m", "Redesigned/Lyrics/LyricsText.m",
    "Shared/Lyrics/KaraokeTiming.m", "Shared/Lyrics/Protobuf.m", "Shared/LyricsSources/SGTTML.m",
    "Redesigned/Kit/SGRTokens.m", "Core/SGLog.m", "Core/SGPrefs.m", "Core/SGGlass.m"]]
command = ["xcrun", "--sdk", "iphonesimulator", "clang", "-target", "arm64-apple-ios26.0-simulator",
           "-fobjc-arc", "-g", "-O1", "-Wall", "-Werror", "-Wno-deprecated-declarations", "-I", str(src),
           "-I", str(src / "Redesigned/Lyrics")]
command += [str(path) for path in sources]
for framework in ["UIKit", "QuartzCore", "CoreGraphics", "CoreText", "Foundation", "AVFoundation"]:
    command += ["-framework", framework]
subprocess.run(command + ["-o", str(app / "LyricsImmersive")], check=True)
for fixture in (here.parent / "lyrics/fixtures").glob("*.ttml"):
    shutil.copyfile(fixture, app / fixture.name)
with (app / "Info.plist").open("wb") as stream:
    plistlib.dump(dict(CFBundleExecutable="LyricsImmersive", CFBundleIdentifier="pw.spoti.harness.immersive",
                      CFBundleName="Lyrics Immersive", CFBundleVersion="1", CFBundleShortVersionString="1.0",
                      UIUserInterfaceStyle="Dark", UILaunchScreen={},
                      UIApplicationSceneManifest={"UIApplicationSupportsMultipleScenes": False}), stream)
subprocess.run(["xattr", "-cr", str(app)], check=True)
subprocess.run(["codesign", "-f", "-s", "-", str(app)], check=True)
print(app)
