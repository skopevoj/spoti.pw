#!/usr/bin/env python3
"""Build a signed, local iPhone model benchmark using Xcode's configured development account."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--model", type=Path, required=True, help="compiled .aimodelc or .mlmodelc directory")
parser.add_argument("--goldens", type=Path, required=True, help="export_model.py output with golden_raw/vocals.f32")
parser.add_argument("--team", required=True, help="development team configured in Xcode")
parser.add_argument("--build-dir", type=Path, help="generated project and app output; use a local cache outside cloud-synced folders")
args = parser.parse_args()
model = args.model.resolve()
if model.suffix not in (".aimodelc", ".mlmodelc") or not model.is_dir():
    parser.error("--model must be a compiled .aimodelc or .mlmodelc directory")
for name in ("golden_raw.f32", "golden_vocals.f32"):
    if not (args.goldens / name).is_file():
        parser.error("missing " + name)
here = Path(__file__).resolve().parent
out = args.build_dir.resolve() if args.build_dir else here / "build/device"
if out.exists():
    if not (out / "SingBenchmark.xcodeproj/project.pbxproj").is_file():
        parser.error("--build-dir already exists and is not a generated SingBenchmark project")
    shutil.rmtree(out)
project = out / "SingBenchmark.xcodeproj"
project.mkdir(parents=True)
assets = out / "Assets"
assets.mkdir()
shutil.copyfile(here / "device.swift", out / "Main.swift")
for name in ("SGStemSeparator.swift", "SGStemCoreMLSeparator.swift"):
    shutil.copyfile(here.parent.parent / "tweak/Sources/Shared/Sing" / name, out / name)
subprocess.run(["cp", "-cR", str(model), str(assets / ("separator" + model.suffix))], check=True)
for name in ("golden_raw.f32", "golden_vocals.f32"):
    shutil.copyfile(args.goldens / name, assets / name)
hashes = {}
for path in model.rglob("*"):
    if path.is_file():
        with path.open("rb") as stream:
            hashes[str(path.relative_to(model))] = hashlib.file_digest(stream, "sha256").hexdigest()
(assets / "hashes.json").write_text(json.dumps(hashes, indent=2) + "\n")
(project / "project.pbxproj").write_text("""// !$*UTF8*$!
{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {
 A00000000000000000000001 = {isa = PBXProject; buildConfigurationList = A00000000000000000000002; compatibilityVersion = "Xcode 14.0"; mainGroup = A00000000000000000000003; projectDirPath = ""; projectRoot = ""; targets = (A00000000000000000000004,); attributes = {LastUpgradeCheck = 2700;};};
 A00000000000000000000002 = {isa = XCConfigurationList; buildConfigurations = (A00000000000000000000005,); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;};
 A00000000000000000000003 = {isa = PBXGroup; children = (A00000000000000000000007,A00000000000000000000008,A00000000000000000000011,A00000000000000000000009,A0000000000000000000000A,); sourceTree = "<group>";};
 A00000000000000000000004 = {isa = PBXNativeTarget; name = SingBenchmark; productName = SingBenchmark; productReference = A0000000000000000000000A; productType = "com.apple.product-type.application"; buildConfigurationList = A0000000000000000000000B; buildPhases = (A0000000000000000000000C,A0000000000000000000000D,); buildRules = (); dependencies = ();};
 A00000000000000000000005 = {isa = XCBuildConfiguration; name = Release; buildSettings = {SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 27.0; SWIFT_VERSION = 5.0; SWIFT_OPTIMIZATION_LEVEL = "-O";};};
 A00000000000000000000006 = {isa = XCBuildConfiguration; name = Release; buildSettings = {PRODUCT_NAME = SingBenchmark; PRODUCT_BUNDLE_IDENTIFIER = "pw.spoti.harness.sing"; CODE_SIGN_STYLE = Automatic; ALWAYS_SEARCH_USER_PATHS = NO; GENERATE_INFOPLIST_FILE = YES; INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES; INFOPLIST_KEY_UILaunchScreen_Generation = YES; TARGETED_DEVICE_FAMILY = 1; CURRENT_PROJECT_VERSION = 1; MARKETING_VERSION = 1.0;};};
 A00000000000000000000007 = {isa = PBXFileReference; path = Main.swift; lastKnownFileType = sourcecode.swift; sourceTree = "<group>";};
 A00000000000000000000008 = {isa = PBXFileReference; path = SGStemSeparator.swift; lastKnownFileType = sourcecode.swift; sourceTree = "<group>";};
 A00000000000000000000009 = {isa = PBXFileReference; path = Assets; lastKnownFileType = folder; sourceTree = "<group>";};
 A0000000000000000000000A = {isa = PBXFileReference; path = SingBenchmark.app; explicitFileType = wrapper.application; sourceTree = BUILT_PRODUCTS_DIR;};
 A0000000000000000000000B = {isa = XCConfigurationList; buildConfigurations = (A00000000000000000000006,); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;};
 A0000000000000000000000C = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (A0000000000000000000000E,A0000000000000000000000F,A00000000000000000000012,); runOnlyForDeploymentPostprocessing = 0;};
 A0000000000000000000000D = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (A00000000000000000000010,); runOnlyForDeploymentPostprocessing = 0;};
 A0000000000000000000000E = {isa = PBXBuildFile; fileRef = A00000000000000000000007;};
 A0000000000000000000000F = {isa = PBXBuildFile; fileRef = A00000000000000000000008;};
 A00000000000000000000010 = {isa = PBXBuildFile; fileRef = A00000000000000000000009;};
 A00000000000000000000011 = {isa = PBXFileReference; path = SGStemCoreMLSeparator.swift; lastKnownFileType = sourcecode.swift; sourceTree = "<group>";};
 A00000000000000000000012 = {isa = PBXBuildFile; fileRef = A00000000000000000000011;};
 }; rootObject = A00000000000000000000001; }
""")
subprocess.run(["xcodebuild", "-project", str(project), "-scheme", "SingBenchmark", "-configuration", "Release",
                "-destination", "generic/platform=iOS", "-derivedDataPath", str(out / "derived"),
                "-allowProvisioningUpdates", "DEVELOPMENT_TEAM=" + args.team, "build"], check=True)
print(out / "derived/Build/Products/Release-iphoneos/SingBenchmark.app")
