#!/usr/bin/env python3
"""Make a new IPA from a released one plus a fresh Kodi and Aether bridge build.

Usage: repackage_release.py BASE_IPA KODI_APP BRIDGE_PRODUCTS OUTPUT_FOLDER [ADDONS]

BASE_IPA         a released DexHub IPA; its bundled add-ons, fonts, licences and
                 Python compatibility files are kept as they are
KODI_APP         Kodi.app from integrate.sh's xcodebuild (Release-appletvos)
BRIDGE_PRODUCTS  Release-appletvos folder of the DexAetherBridge build
ADDONS           a folder of add-on folders (plugin.video.dexhub.tvos, skin.dexhub.tvos,
                 script.dexhub.tvos.players...) that replace the released copies whole

Every file Kodi's build produces replaces the released copy (binary, asset
catalogue, splash, system files, top shelf extension), except the add-ons
DexHubBundle.json lists. The Aether frameworks and resources come from the
bridge build, signed ad hoc for re-signing as normalize_frameworks.sh does.
"""
import json
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from datetime import datetime, timedelta, timezone
from pathlib import Path

base_ipa, kodi_app, products, output = map(Path, sys.argv[1:5])
addons = Path(sys.argv[5]) if len(sys.argv) > 5 else None
updates = {}
for folder in sorted(addons.iterdir()) if addons else []:
    descriptor = folder / 'addon.xml'
    if descriptor.is_file():
        version = re.search(r'<addon\b[^>]*\sversion="([^"]+)"', descriptor.read_text(encoding='utf-8'))
        updates[folder.name] = (folder, version.group(1) if version else '')
repo = Path(__file__).resolve().parent
release = json.loads((repo / 'ENGINE-RELEASE.json').read_text())
APP = 'Payload/Kodi.app/'
ADDONS = APP + 'AppData/AppHome/addons/'
now = datetime.now(timezone(timedelta(hours=3)))

with tempfile.TemporaryDirectory(dir=output) as temporary:
    stage = Path(temporary) / 'Kodi.app'
    shutil.copytree(kodi_app, stage, symlinks=True)
    shutil.rmtree(stage / '_CodeSignature', ignore_errors=True)
    frameworks = stage / 'Frameworks'
    frameworks.mkdir(exist_ok=True)
    for framework in products.glob('*.framework'):
        if framework.name.startswith('Aether') or framework.name == 'DexAetherBridge.framework':
            shutil.copytree(framework, frameworks / framework.name, symlinks=True, dirs_exist_ok=True)
    shutil.copytree(repo / 'vendor/DexNavigationKit.framework', frameworks / 'DexNavigationKit.framework',
                    dirs_exist_ok=True)
    resources = products / 'AetherEngine_AetherEngine.bundle'
    if not (resources / 'silent-atmos.mp4').is_file():
        raise SystemExit('Aether resource bundle missing from the bridge build')
    shutil.copytree(resources, stage / resources.name, dirs_exist_ok=True)

    bridge = frameworks / 'DexAetherBridge.framework'
    exports = subprocess.check_output(['nm', '-gU', str(bridge / 'DexAetherBridge')], text=True)
    for api in ('startEmbedded', 'snapshotForToken', 'command'):
        if api not in exports:
            raise SystemExit('Missing native bridge API: ' + api)
    info = plistlib.loads((bridge / 'Info.plist').read_bytes())
    info.update(DexHubBridgeAPI=2, DexHubBridgeRevision=release['bridge_revision'],
                DexHubAetherVersion=release['version'], DexHubAetherCommit=release['commit'])
    (bridge / 'Info.plist').write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_BINARY))
    subprocess.run(['xcrun', 'swift-stdlib-tool', '--copy', '--platform', 'appletvos',
                    '--scan-executable', str(bridge / 'DexAetherBridge'), '--scan-folder', str(frameworks),
                    '--destination', str(frameworks)], check=True)
    subprocess.run(['bash', str(repo / 'normalize_frameworks.sh'), str(stage)], check=True)
    # Python extension modules and the top shelf extension: ad hoc, like the
    # frameworks, so the final signer starts from valid signatures.
    for module in [*stage.glob('lib/**/*.so'), *stage.glob('lib/**/*.dylib')]:
        subprocess.run(['codesign', '--force', '--sign', '-', '--timestamp=none', str(module)],
                       check=True, stdout=subprocess.DEVNULL)
    for extension in stage.glob('PlugIns/*.appex'):
        subprocess.run(['codesign', '--force', '--sign', '-', '--timestamp=none', str(extension)],
                       check=True, stdout=subprocess.DEVNULL)
        subprocess.run(['codesign', '--verify', '--strict', str(extension)], check=True)

    with zipfile.ZipFile(base_ipa) as base:
        names = set(base.namelist())
        manifest = json.loads(base.read(APP + 'AppData/DexHubBundle.json'))
        managed = tuple(ADDONS + item['id'] + '/' for item in manifest['addons'])
        built = {APP + path.relative_to(stage).as_posix(): path for path in stage.rglob('*') if path.is_file()}
        replace = {name: path for name, path in built.items() if not name.startswith(managed)}
        # Updated add-ons replace their released copies whole.
        for identifier, (folder, version) in updates.items():
            for path in folder.rglob('*'):
                if path.is_file() and '__pycache__' not in path.parts and path.suffix != '.pyc' and path.name != '.DS_Store':
                    replace[ADDONS + identifier + '/' + path.relative_to(folder).as_posix()] = path
        # Old engine bundles and frameworks go; the new set replaces them whole.
        drop = (APP + '_CodeSignature/', APP + 'Frameworks/', APP + 'PlugIns/', APP + 'AetherEngine_AetherEngine.bundle/',
                *(ADDONS + identifier + '/' for identifier in updates))

        plist = plistlib.loads((stage / 'Info.plist').read_bytes())
        released = plistlib.loads(base.read(APP + 'Info.plist'))
        for key, value in released.items():
            if key.startswith('DexHub') or key in ('MinimumOSVersion', 'CFBundleURLTypes'):
                plist.setdefault(key, value)
        plist['MinimumOSVersion'] = released['MinimumOSVersion']
        plist.update(DexHubBuildVersion=release['app_version'], DexHubAetherVersion=release['version'],
                     CFBundleVersion=now.strftime('%y%m%d%H%M'))
        manifest.update(app_version=release['app_version'], engine=release['version'])
        listed = {item['id']: item for item in manifest['addons']}
        for identifier, (folder, version) in updates.items():
            listed.setdefault(identifier, {'id': identifier})['version'] = version
        manifest['addons'] = sorted(listed.values(), key=lambda item: item['id'])
        details = {'app_version': release['app_version'], 'engine': release['version'],
                   'engine_commit': release['commit'], 'bridge_revision': release['bridge_revision'],
                   'dependencies': release['dependencies'], 'traits': release['traits'],
                   'built_at': now.isoformat(), 'base_ipa': base_ipa.name}
        generated = {APP + 'Info.plist': plistlib.dumps(plist, fmt=plistlib.FMT_BINARY),
                     APP + 'AppData/DexHubBundle.json': json.dumps(manifest, indent=2).encode(),
                     APP + 'AppData/DexHubBuild.json': json.dumps(details, indent=2).encode()}

        target = output / f"Kodi-DexHub-v{release['app_version']}-Aether{release['version']}-unsigned-{now:%Y%m%d-%H%M%S}.ipa"
        with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as ipa:
            for item in base.infolist():
                if item.filename in replace or item.filename in generated or item.filename.startswith(drop):
                    continue
                ipa.writestr(item, base.read(item))
            for name, path in sorted(replace.items()):
                if name in generated:
                    continue
                entry = zipfile.ZipInfo(name, now.timetuple()[:6])
                entry.create_system = 3
                entry.compress_type = zipfile.ZIP_DEFLATED
                entry.external_attr = (0o100000 | (path.stat().st_mode & 0o777)) << 16
                ipa.writestr(entry, path.read_bytes())
            for name, data in generated.items():
                entry = zipfile.ZipInfo(name, now.timetuple()[:6])
                entry.create_system = 3
                entry.compress_type = zipfile.ZIP_DEFLATED
                entry.external_attr = 0o100644 << 16
                ipa.writestr(entry, data)
        added = sorted(set(replace) - names)
        print(target)
        print('Replaced from the new build:', len(set(replace) & names), 'files; new:', len(added))
        for name in added[:40]:
            print('  +', name)
