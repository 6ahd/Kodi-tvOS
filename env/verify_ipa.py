#!/usr/bin/env python3
"""Check a built IPA before anyone signs it.

Usage: verify_ipa.py NEW_IPA BASE_IPA
Stops with an error when the archive is damaged, a library the app links to
is missing, a framework's signature does not verify, or a bundled Dex Hub
add-on differs from the released one.
"""
import hashlib
import plistlib
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

new_path, base_path = sys.argv[1:3]
APP = 'Payload/Kodi.app/'
DEXHUB = ('plugin.video.dexhub.tvos', 'skin.dexhub.tvos', 'script.dexhub.tvos.players', 'repository.dexworld.appletv')
new, base = zipfile.ZipFile(new_path), zipfile.ZipFile(base_path)
names = new.namelist()
problems = []
if len(names) != len(set(names)):
    problems.append('duplicate archive entries')
if new.testzip() is not None:
    problems.append('damaged archive entry')

digest = lambda z, name: hashlib.sha256(z.read(name)).hexdigest()
for name in base.namelist():
    parts = name.split('/')
    if len(parts) > 5 and parts[4] in DEXHUB and not name.endswith('/'):
        if name not in names or digest(base, name) != digest(new, name):
            problems.append('Dex Hub add-on file changed: ' + name)
            break

info = plistlib.loads(new.read(APP + 'Info.plist'))
with tempfile.TemporaryDirectory() as folder:
    new.extractall(folder)
    app = Path(folder) / APP
    binaries = [app / 'Kodi'] + [f / f.stem for f in (app / 'Frameworks').glob('*.framework')]
    for binary in binaries:
        for line in subprocess.check_output(['otool', '-L', str(binary)], text=True).splitlines()[1:]:
            dependency = line.strip().split(' ')[0]
            if dependency.startswith('@rpath/') and not (app / 'Frameworks' / dependency[7:]).exists():
                problems.append(f'{binary.name} needs missing {dependency}')
    for bundle in list((app / 'Frameworks').glob('*.framework')) + list((app / 'PlugIns').glob('*.appex')):
        if subprocess.run(['codesign', '--verify', '--strict', str(bundle)], capture_output=True).returncode:
            problems.append('signature does not verify: ' + bundle.name)
    platform = subprocess.check_output(['vtool', '-show-build', str(app / 'Kodi')], text=True)
    if 'TVOS' not in platform:
        problems.append('Kodi binary is not built for tvOS')
    apple_ui = (app / 'Frameworks/DexAppleUI.framework').is_dir()

if problems:
    raise SystemExit('IPA check failed:\n  ' + '\n  '.join(problems))
print('IPA check passed: %d entries, Dex Hub add-ons unchanged, libraries complete, signatures valid' % len(names))
print('  %s %s · build %s · Aether %s · Apple mode %s' % (info.get('CFBundleDisplayName'), info.get('DexHubBuildVersion'),
      info.get('CFBundleVersion'), info.get('DexHubAetherVersion'), 'included' if apple_ui else 'MISSING'))
