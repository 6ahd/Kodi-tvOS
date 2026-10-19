#!/usr/bin/env python3
import json
import sys
from pathlib import Path

root = Path(__file__).resolve().parent
engine = Path(sys.argv[1]).resolve()
if not (engine / 'Package.swift').is_file():
    raise SystemExit('AetherEngine/Package.swift is missing')
q = json.dumps(str(engine))
project = root / 'DexAetherBridge.xcodeproj'
project.mkdir(exist_ok=True)
pbx = '''// !$*UTF8*$!
{
 archiveVersion = 1;
 classes = {};
 objectVersion = 56;
 objects = {
  A00000000000000000000001 = {isa = PBXProject; attributes = {LastUpgradeCheck = 1600;}; buildConfigurationList = A00000000000000000000010; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = A00000000000000000000002; productRefGroup = A00000000000000000000003; projectDirPath = ""; projectRoot = ""; targets = (A00000000000000000000004); packageReferences = (A00000000000000000000020);};
  A00000000000000000000002 = {isa = PBXGroup; children = (A00000000000000000000005, A00000000000000000000023, A00000000000000000000003); sourceTree = "<group>";};
  A00000000000000000000003 = {isa = PBXGroup; children = (A00000000000000000000006); name = Products; sourceTree = "<group>";};
  A00000000000000000000004 = {isa = PBXNativeTarget; buildConfigurationList = A00000000000000000000011; buildPhases = (A00000000000000000000007, A00000000000000000000008); buildRules = (); dependencies = (); name = DexAetherBridge; productName = DexAetherBridge; productReference = A00000000000000000000006; productType = "com.apple.product-type.framework"; packageProductDependencies = (A00000000000000000000021);};
  A00000000000000000000005 = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DexAetherEmbedded.swift; sourceTree = "<group>";};
  A00000000000000000000006 = {isa = PBXFileReference; explicitFileType = wrapper.framework; includeInIndex = 0; path = DexAetherBridge.framework; sourceTree = BUILT_PRODUCTS_DIR;};
  A00000000000000000000007 = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (A00000000000000000000009, A00000000000000000000024); runOnlyForDeploymentPostprocessing = 0;};
  A00000000000000000000008 = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (A00000000000000000000022); runOnlyForDeploymentPostprocessing = 0;};
  A00000000000000000000009 = {isa = PBXBuildFile; fileRef = A00000000000000000000005;};
  A00000000000000000000010 = {isa = XCConfigurationList; buildConfigurations = (A00000000000000000000012, A00000000000000000000013); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;};
  A00000000000000000000011 = {isa = XCConfigurationList; buildConfigurations = (A00000000000000000000014, A00000000000000000000015); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;};
  A00000000000000000000012 = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = appletvos; TVOS_DEPLOYMENT_TARGET = 17.0;}; name = Debug;};
  A00000000000000000000013 = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = appletvos; TVOS_DEPLOYMENT_TARGET = 17.0;}; name = Release;};
  A00000000000000000000014 = {isa = XCBuildConfiguration; buildSettings = {__SETTINGS__}; name = Debug;};
  A00000000000000000000015 = {isa = XCBuildConfiguration; buildSettings = {__SETTINGS__}; name = Release;};
  A00000000000000000000020 = {isa = XCLocalSwiftPackageReference; relativePath = __ENGINE__;};
  A00000000000000000000021 = {isa = XCSwiftPackageProductDependency; package = A00000000000000000000020; productName = AetherEngine;};
  A00000000000000000000022 = {isa = PBXBuildFile; productRef = A00000000000000000000021;};
  A00000000000000000000023 = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SubtitleWindowIndex.swift; sourceTree = "<group>";};
  A00000000000000000000024 = {isa = PBXBuildFile; fileRef = A00000000000000000000023;};
 };
 rootObject = A00000000000000000000001;
}
'''
settings = '''PRODUCT_NAME = "$(TARGET_NAME)";
PRODUCT_BUNDLE_IDENTIFIER = cc.dexworld.DexAetherBridge;
GENERATE_INFOPLIST_FILE = YES; DEFINES_MODULE = YES;
INFOPLIST_KEY_DexHubBridgeAPI = 2;
SWIFT_VERSION = 5.0; SWIFT_OPTIMIZATION_LEVEL = "-O";
CLANG_ENABLE_MODULES = YES; CLANG_ENABLE_OBJC_ARC = YES;
MACH_O_TYPE = mh_dylib; SKIP_INSTALL = NO;
TVOS_DEPLOYMENT_TARGET = 17.0; TARGETED_DEVICE_FAMILY = 3;
LD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@loader_path/..", "@executable_path/Frameworks");
EXPORTED_SYMBOLS_FILE = "$(SRCROOT)/bridge-exports.txt";
CODE_SIGNING_ALLOWED = NO; CODE_SIGNING_REQUIRED = NO;'''
(project / 'project.pbxproj').write_text(pbx.replace('__ENGINE__', q).replace('__SETTINGS__', settings))
(root / 'bridge-exports.txt').write_text('_$s15DexAetherBridge*\n_OBJC_CLASS_$_DexAetherBridge\n_OBJC_METACLASS_$_DexAetherBridge\n')
print(project)
