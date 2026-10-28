#!/usr/bin/env python3
"""Apply the DexHub Kodi changes to a clean Kodi 22.0rc1-Piers checkout.

Usage: apply_kodi_patch.py KODI_SOURCE [--check]
native/kodi-22.0rc1-dexhub.patch holds every DexHub change to Kodi's source
(Aether player core, setup, input, Now Playing, Back on the Home screen).
A checkout that already carries the patch is left as it is. Any other state
stops the build without touching a file.
"""
import subprocess
import sys
from pathlib import Path

PATCH = Path(__file__).resolve().parent / 'native/kodi-22.0rc1-dexhub.patch'
source = Path(sys.argv[1]).resolve()
check = '--check' in sys.argv[2:]


def git_apply(*args):
    return subprocess.run(['git', '-C', str(source), 'apply', '--whitespace=nowarn', *args, str(PATCH)],
                          capture_output=True, text=True)


if git_apply('--reverse', '--check').returncode == 0:
    print('DexHub Kodi patch already applied:', source)
elif git_apply('--check').returncode == 0:
    if not check:
        result = git_apply()
        if result.returncode:
            raise SystemExit(result.stderr)
    print('DexHub Kodi patch', 'applies' if check else 'applied', 'to', source)
else:
    raise SystemExit('Kodi source differs from 22.0rc1-Piers and from this patch; no files changed.\n'
                     'Start from a clean checkout: bash update-kodi.sh 22.0rc1-Piers\n'
                     + git_apply('--check').stderr)
