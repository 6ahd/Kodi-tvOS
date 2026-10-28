#!/usr/bin/env python3
"""Bring the newest general Dex Hub add-on and skin to Apple TV, if there are newer ones.

Usage: sync_from_general.py GENERAL STATE
  GENERAL  the folder the general releases land in (plugin.video.dexhub-<v>.zip,
           skin.dexhub-<v>.zip; older ones move away)
  STATE    where the Apple TV copies live: STATE/tvos/<id>/ and, beside them,
           STATE/general/ holding the general zip each copy now matches

A newer general zip is merged into the Apple TV copy with tvos_sync.py (the
Apple TV changes stay). The copy is replaced only when the merge is clean.
"""
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

KINDS = (('plugin.video.dexhub', 'plugin.video.dexhub.tvos'), ('skin.dexhub', 'skin.dexhub.tvos'))
tool = Path(__file__).resolve().parent / 'tvos_sync.py'


def version(path):
    match = re.search(r'-(\d+(?:\.\d+)*)\.zip$', path.name)
    return tuple(int(part) for part in match.group(1).split('.')) if match else ()


def newest(folder, general_id):
    found = [p for p in folder.glob(general_id + '-*.zip') if version(p)]
    return max(found, key=version) if found else None


def main():
    general, state = Path(sys.argv[1]), Path(sys.argv[2])
    failed = False
    for general_id, tvos_id in KINDS:
        latest = newest(general, general_id)
        base = newest(state / 'general', general_id)
        ours = state / 'tvos' / tvos_id
        if not latest or not base or not ours.is_dir():
            print('%s: missing General zip, base or Apple TV copy; left as it is' % tvos_id)
            failed = True
            continue
        number = '.'.join(map(str, version(latest)))
        if version(latest) <= version(base):
            print('%s %s: up to date with General' % (tvos_id, '.'.join(map(str, version(base)))))
            continue
        with tempfile.TemporaryDirectory(dir=state) as scratch:
            result = subprocess.run([sys.executable, str(tool), str(base), str(ours), str(latest), scratch, number],
                                    capture_output=True, text=True)
            print(result.stdout.strip())
            if result.returncode:
                print(result.stderr.strip())
                print('%s: %s needs a hand merge; the Apple TV copy stays at %s' % (tvos_id, number, base.name))
                failed = True
                continue
            shutil.rmtree(ours)
            shutil.move(str(Path(scratch) / tvos_id), str(ours))
        base.unlink()
        shutil.copy2(latest, state / 'general' / latest.name)
        print('%s: now %s (from %s)' % (tvos_id, number, latest.name))
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
