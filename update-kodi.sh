#!/usr/bin/env bash
set -euo pipefail
BASE="$(cd "$(dirname "$0")" && pwd)"
WORK="${DEX_WORK:-$HOME/Developer/DexHub-tvOS}"
TAG="${1:?Usage: bash update-kodi.sh EXACT_KODI_TAG}"
case "$TAG" in *[!a-zA-Z0-9._-]*|'') echo "Use an exact Kodi release tag."; exit 1;; esac
export KODI_SRC="$WORK/kodi-$TAG-source"
export KODI_BUILD="$WORK/kodi-$TAG-tvos-build"
mkdir -p "$WORK"
if [ ! -d "$KODI_SRC" ]; then
  git ls-remote --exit-code --tags https://github.com/xbmc/xbmc.git "refs/tags/$TAG" >/dev/null
  git clone --depth 1 --branch "$TAG" https://github.com/xbmc/xbmc.git "$KODI_SRC"
fi
[ -d "$KODI_SRC/.git" ] || { echo "Destination is not a Kodi checkout."; exit 1; }
CURRENT="$(git -C "$KODI_SRC" rev-parse HEAD)"
EXPECTED="$(git -C "$KODI_SRC" rev-parse "refs/tags/$TAG^{commit}")"
[ "$CURRENT" = "$EXPECTED" ] || { echo "Checkout differs from requested tag; no files changed."; exit 1; }
python3 "$BASE/apply_kodi_patch.py" "$KODI_SRC" --check
if [ -x /opt/homebrew/opt/m4/bin/m4 ]; then export M4=/opt/homebrew/opt/m4/bin/m4; fi
NATIVE="${DEX_NATIVE:-$(find /Users/Shared/xbmc-depends -maxdepth 1 -type d -name '*-native' | sort | tail -1)}"
export PATH="$NATIVE/bin:/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
cd "$KODI_SRC/tools/depends"
./bootstrap
# Release dependencies (optimized). Debug ones left SQLite and others unoptimized.
./configure --host=aarch64-apple-darwin --with-platform=tvos --enable-debug=no
make -j"${DEX_JOBS:-$(sysctl -n hw.ncpu)}"
if [ -d "$BASE/src/plugin.video.dexhub.tvos" ]; then python3 "$BASE/release_assets.py"; else bash "$BASE/get-dexhub.sh"; fi
bash "$BASE/all.sh"
