#!/usr/bin/env bash
set -euo pipefail
BASE="$(cd "$(dirname "$0")" && pwd)"
WORK="${DEX_WORK:-$HOME/Developer/DexHub-tvOS}"
python3 "$BASE/apply_kodi_patch.py" "${KODI_SRC:-$WORK/kodi-rc1-source}" --check
bash "$BASE/build.sh"
bash "$BASE/integrate.sh"
