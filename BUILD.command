#!/usr/bin/env bash
set -euo pipefail
BASE="$(cd "$(dirname "$0")" && pwd)"
WORK="${DEX_WORK:-$HOME/Developer/DexHub-tvOS}"
if [ "$(uname -s)" != Darwin ]; then
  echo "This build requires your prepared Mac with Xcode."
  exit 1
fi
if [ ! -d "$WORK/kodi-rc1-source" ]; then
  echo "Kodi source not found: $WORK/kodi-rc1-source"
  echo "Keep the existing Kodi source and dependency folders."
  exit 1
fi
AVAILABLE_KB="$(df -Pk "$WORK" | awk 'END {print $4}')"
case "$AVAILABLE_KB" in
  ''|*[!0-9]*) echo "Could not determine free disk space."; exit 1 ;;
esac
# v20.1: once the Aether 7.40.1 bridge and its packages are on this Mac, a rebuild is
# incremental (Kodi objects already exist), so 10 GiB is enough. A first build needs 20.
NEED_KB=20971520
PLIST="$WORK/aether-bridge-build/Products/Release-appletvos/DexAetherBridge.framework/Info.plist"
# v21.34: an existing Kodi build makes this incremental even when the Aether
# version changes (only the bridge and its packages are new: a few GiB)
if { [ -f "$PLIST" ] && [ -d "$WORK/aether-bridge-build/SourcePackages/checkouts/FFmpegBuild" ]; } || \
   [ -d "$WORK/kodi-tvos17-build/build" ]; then
  NEED_KB=10485760
fi
if [ "$AVAILABLE_KB" -lt "$NEED_KB" ]; then
  echo "Less than $((NEED_KB / 1048576)) GiB free. Aether's updated binary dependencies need space."
  echo "Free space safely first; required space varies with the existing build."
  df -h "$WORK"
  exit 1
fi
echo "Kodi AetherOnly v21.42 TEST: Aether 7.40.1 / DexHub 5.10.342 / Skin 3.28.79 / Players 1.0.15 / Release / idle GUI while playing"
echo "The Apple TV addon does not need to be running to build on this Mac."
cd "$BASE"
bash "$BASE/all.sh"
