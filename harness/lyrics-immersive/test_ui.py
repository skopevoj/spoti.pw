#!/usr/bin/env python3
"""Build and run actual touch tests on an already booted iOS 26+ simulator."""
import argparse
from pathlib import Path
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("simulator", help="UDID of an already booted simulator")
args = parser.parse_args()
here = Path(__file__).resolve().parent
out = here / "build/ui"
if out.exists():
    shutil.rmtree(out)
project = out / "LyricsUI.xcodeproj"
schemes = project / "xcshareddata/xcschemes"
schemes.mkdir(parents=True)
shutil.copyfile(here / "UITests.swift", out / "UITests.swift")
(project / "project.pbxproj").write_text("""// !$*UTF8*$!
{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {
 A00000000000000000000001 = {isa = PBXProject; buildConfigurationList = A00000000000000000000002; compatibilityVersion = "Xcode 14.0"; mainGroup = A00000000000000000000003; projectDirPath = ""; projectRoot = ""; targets = (A00000000000000000000004,); attributes = {LastUpgradeCheck = 2700;};};
 A00000000000000000000002 = {isa = XCConfigurationList; buildConfigurations = (A00000000000000000000005,); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;};
 A00000000000000000000003 = {isa = PBXGroup; children = (A00000000000000000000007,A0000000000000000000000A,); sourceTree = "<group>";};
 A00000000000000000000004 = {isa = PBXNativeTarget; name = LyricsUI; productName = LyricsUI; productReference = A0000000000000000000000A; productType = "com.apple.product-type.bundle.ui-testing"; buildConfigurationList = A0000000000000000000000B; buildPhases = (A0000000000000000000000C,A0000000000000000000000D,); buildRules = (); dependencies = ();};
 A00000000000000000000005 = {isa = XCBuildConfiguration; name = Release; buildSettings = {SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 26.0; SWIFT_VERSION = 5.0; SWIFT_OPTIMIZATION_LEVEL = "-O";};};
 A00000000000000000000006 = {isa = XCBuildConfiguration; name = Release; buildSettings = {PRODUCT_NAME = LyricsUI; PRODUCT_BUNDLE_IDENTIFIER = "pw.spoti.harness.uitests"; CODE_SIGN_STYLE = Automatic; GENERATE_INFOPLIST_FILE = YES; ALWAYS_SEARCH_USER_PATHS = NO; TARGETED_DEVICE_FAMILY = 1; CURRENT_PROJECT_VERSION = 1; MARKETING_VERSION = 1.0;};};
 A00000000000000000000007 = {isa = PBXFileReference; path = UITests.swift; lastKnownFileType = sourcecode.swift; sourceTree = "<group>";};
 A0000000000000000000000A = {isa = PBXFileReference; path = LyricsUI.xctest; explicitFileType = wrapper.cfbundle; sourceTree = BUILT_PRODUCTS_DIR;};
 A0000000000000000000000B = {isa = XCConfigurationList; buildConfigurations = (A00000000000000000000006,); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;};
 A0000000000000000000000C = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (A0000000000000000000000E,); runOnlyForDeploymentPostprocessing = 0;};
 A0000000000000000000000D = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;};
 A0000000000000000000000E = {isa = PBXBuildFile; fileRef = A00000000000000000000007;};
 }; rootObject = A00000000000000000000001; }""")
(schemes / "LyricsUI.xcscheme").write_text("""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
<BuildAction parallelizeBuildables="NO" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="A00000000000000000000004" BuildableName="LyricsUI.xctest" BlueprintName="LyricsUI" ReferencedContainer="container:LyricsUI.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="NO"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="A00000000000000000000004" BuildableName="LyricsUI.xctest" BlueprintName="LyricsUI" ReferencedContainer="container:LyricsUI.xcodeproj"/></TestableReference></Testables></TestAction>
</Scheme>""")

subprocess.run(["python3", str(here / "build.py")], check=True)
subprocess.run(["xcrun", "simctl", "install", args.simulator, str(here / "build/LyricsImmersive.app")], check=True)
subprocess.run(["xcodebuild", "-project", str(project), "-scheme", "LyricsUI",
                "-destination", "id=" + args.simulator, "-derivedDataPath", str(out / "derived"),
                "-parallel-testing-enabled", "NO", "-maximum-concurrent-test-simulator-destinations", "1",
                "-collect-test-diagnostics", "never",
                "-resultBundlePath", str(out / "results.xcresult"), "test"], check=True)
