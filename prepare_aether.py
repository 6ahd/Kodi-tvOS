#!/usr/bin/env python3
"""Fetch one reviewed release into its own checkout, preserving Nuvio's vendor."""
import json
import re
import subprocess
import sys
from pathlib import Path

RELEASE = json.loads((Path(__file__).resolve().parent / 'ENGINE-RELEASE.json').read_text())
TAG = RELEASE['version']
COMMIT = RELEASE['commit']
DEPENDENCIES = RELEASE['dependencies']


def prepare(work):
    root = Path(work) / 'dexhub-engine-sources' / ('AetherEngine-' + TAG)
    if not root.exists():
        root.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(['git', 'clone', '--depth', '1', '--branch', TAG,
                        'https://github.com/superuser404notfound/AetherEngine.git', str(root)], check=True)
    actual = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip()
    if actual != COMMIT:
        raise SystemExit('Aether checkout has another commit; use a new DEX_WORK directory.')
    manifest = root / 'Package.swift'
    original = subprocess.check_output(['git', '-C', str(root), 'show', 'HEAD:Package.swift'], text=True)
    pinned = original
    for name, version in DEPENDENCIES.items():
        pattern = r'(\.package\(url: "[^"]*/' + re.escape(name) + r'", )\.upToNextMinor\(from: "' + re.escape(version) + r'"\)'
        pinned, count = re.subn(pattern, lambda match: match[1] + 'exact: "' + version + '"', pinned)
        if count != 1: raise SystemExit('Dependency pin anchor changed: ' + name)
    trait_anchor = '.default(enabledTraits: [])'
    if pinned.count(trait_anchor) != 1:
        raise SystemExit('Aether default traits anchor changed')
    traits = ', '.join(json.dumps(name) for name in RELEASE['traits'])
    pinned = pinned.replace(trait_anchor, '.default(enabledTraits: [' + traits + '])')
    if manifest.read_text() not in (original, pinned):
        raise SystemExit('Aether manifest has local edits; refusing to overwrite them.')
    manifest.write_text(pinned)
    (root / 'DexHubEngine.json').write_text(json.dumps(RELEASE, indent=2))
    return root


if __name__ == '__main__':
    print(prepare(sys.argv[1]))
