#!/usr/bin/env python3
"""Write DexAppleUI.xcodeproj: the DexAppleUI framework Kodi loads, and
DexAppleUIPreview, the same screens on sample data for the tvOS simulator."""
from pathlib import Path

root = Path(__file__).resolve().parent
sources = sorted(p.name for p in (root / 'Sources').glob('*.swift'))
preview = sorted(p.name for p in (root / 'Preview').glob('*.swift'))
counter = iter(range(1, 10_000))
objects = []


def oid():
    return 'D%023X' % next(counter)


def add(text):
    objects.append(text)


project, main_group, products_group, sources_group, preview_group = oid(), oid(), oid(), oid(), oid()
framework_target, app_target = oid(), oid()
framework_product, app_product = oid(), oid()
project_configs, framework_configs, app_configs = oid(), oid(), oid()


def file_refs(names, folder):
    refs = []
    for name in names:
        ref = oid()
        add(f'{ref} = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {folder}/{name}; sourceTree = SOURCE_ROOT;}};')
        refs.append(ref)
    return refs


source_refs = file_refs(sources, 'Sources')
preview_refs = file_refs(preview, 'Preview')


def sources_phase(refs):
    phase, builds = oid(), []
    for ref in refs:
        build = oid()
        add(f'{build} = {{isa = PBXBuildFile; fileRef = {ref};}};')
        builds.append(build)
    add(f'{phase} = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({", ".join(builds)}); runOnlyForDeploymentPostprocessing = 0;}};')
    return phase


common = ('SDKROOT = appletvos; SUPPORTED_PLATFORMS = "appletvos appletvsimulator"; TARGETED_DEVICE_FAMILY = 3; '
          'TVOS_DEPLOYMENT_TARGET = 26.0; SWIFT_VERSION = 5.0; SWIFT_OPTIMIZATION_LEVEL = "-O"; '
          'GENERATE_INFOPLIST_FILE = YES; CODE_SIGNING_ALLOWED = NO; CODE_SIGNING_REQUIRED = NO; '
          'CURRENT_PROJECT_VERSION = 1; ALWAYS_SEARCH_USER_PATHS = NO; MARKETING_VERSION = 1.0;')
framework_settings = (common + ' PRODUCT_NAME = DexAppleUI; PRODUCT_BUNDLE_IDENTIFIER = cc.dexworld.DexAppleUI; '
                      'DEFINES_MODULE = YES; MACH_O_TYPE = mh_dylib; SKIP_INSTALL = NO; '
                      'LD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks");')
app_settings = (common + ' PRODUCT_NAME = DexAppleUIPreview; PRODUCT_BUNDLE_IDENTIFIER = cc.dexworld.DexAppleUIPreview; '
                'INFOPLIST_KEY_UILaunchScreen_Generation = YES; INFOPLIST_KEY_CFBundleDisplayName = "Dex Hub Preview"; '
                'LD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/Frameworks");')

for configs, settings in ((project_configs, common), (framework_configs, framework_settings), (app_configs, app_settings)):
    names = []
    for name in ('Debug', 'Release'):
        config = oid()
        add(f'{config} = {{isa = XCBuildConfiguration; buildSettings = {{{settings}}}; name = {name};}};')
        names.append(config)
    add(f'{configs} = {{isa = XCConfigurationList; buildConfigurations = ({", ".join(names)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;}};')

framework_phase = sources_phase(source_refs)
app_phase = sources_phase(source_refs + preview_refs)
add(f'{framework_product} = {{isa = PBXFileReference; explicitFileType = wrapper.framework; includeInIndex = 0; path = DexAppleUI.framework; sourceTree = BUILT_PRODUCTS_DIR;}};')
add(f'{app_product} = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = DexAppleUIPreview.app; sourceTree = BUILT_PRODUCTS_DIR;}};')
add(f'{framework_target} = {{isa = PBXNativeTarget; buildConfigurationList = {framework_configs}; buildPhases = ({framework_phase}); buildRules = (); dependencies = (); name = DexAppleUI; productName = DexAppleUI; productReference = {framework_product}; productType = "com.apple.product-type.framework";}};')
add(f'{app_target} = {{isa = PBXNativeTarget; buildConfigurationList = {app_configs}; buildPhases = ({app_phase}); buildRules = (); dependencies = (); name = DexAppleUIPreview; productName = DexAppleUIPreview; productReference = {app_product}; productType = "com.apple.product-type.application";}};')
add(f'{sources_group} = {{isa = PBXGroup; children = ({", ".join(source_refs)}); name = Sources; sourceTree = "<group>";}};')
add(f'{preview_group} = {{isa = PBXGroup; children = ({", ".join(preview_refs)}); name = Preview; sourceTree = "<group>";}};')
add(f'{products_group} = {{isa = PBXGroup; children = ({framework_product}, {app_product}); name = Products; sourceTree = "<group>";}};')
add(f'{main_group} = {{isa = PBXGroup; children = ({sources_group}, {preview_group}, {products_group}); sourceTree = "<group>";}};')
add(f'{project} = {{isa = PBXProject; attributes = {{LastUpgradeCheck = 2700;}}; buildConfigurationList = {project_configs}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, ar, Base); mainGroup = {main_group}; productRefGroup = {products_group}; projectDirPath = ""; projectRoot = ""; targets = ({framework_target}, {app_target});}};')

folder = root / 'DexAppleUI.xcodeproj'
folder.mkdir(exist_ok=True)
(folder / 'project.pbxproj').write_text('// !$*UTF8*$!\n{\n archiveVersion = 1;\n classes = {};\n objectVersion = 56;\n objects = {\n  '
                                        + '\n  '.join(objects) + f'\n }};\n rootObject = {project};\n}}\n')
print(folder)
