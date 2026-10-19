#!/usr/bin/env bash
set -euo pipefail
BASE="$(cd "$(dirname "$0")" && pwd)"
WORK="${DEX_WORK:-$HOME/Developer/DexHub-tvOS}"
NATIVE="${DEX_NATIVE:-}"
if [ -z "$NATIVE" ]; then
  NATIVE="$(find /Users/Shared/xbmc-depends -maxdepth 1 -type d -name '*-native' | sort | tail -1)"
fi
[ -x "$NATIVE/bin/python3" ] || { echo "Set DEX_NATIVE to the native Kodi dependency directory."; exit 1; }
export PATH="$NATIVE/bin:/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
PYTHON="$NATIVE/bin/python3"
BUILD="$WORK/aether-bridge-build"
mkdir -p "$BUILD"
ENGINE="$("$PYTHON" "$BASE/prepare_aether.py" "$WORK")"
"$PYTHON" "$BASE/generate_project.py" "$ENGINE"
xcodebuild -resolvePackageDependencies -project "$BASE/DexAetherBridge.xcodeproj" \
  -scheme DexAetherBridge -clonedSourcePackagesDirPath "$BUILD/SourcePackages" \
  2>&1 | tee "$BUILD/package-resolve.log"

"$PYTHON" "$BASE/preflight.py" "$BUILD/SourcePackages" "$BUILD/deployment.txt" | tee "$BUILD/preflight.log"
MINIMUM="$(cat "$BUILD/deployment.txt")"
echo "Bridge minimum tvOS: $MINIMUM"

xcodebuild -project "$BASE/DexAetherBridge.xcodeproj" \
  -target DexAetherBridge -configuration Release -sdk appletvos -jobs "$(sysctl -n hw.ncpu)" \
  -clonedSourcePackagesDirPath "$BUILD/SourcePackages" \
  SYMROOT="$BUILD/Products" OBJROOT="$BUILD/Intermediates" \
  TVOS_DEPLOYMENT_TARGET="$MINIMUM" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build 2>&1 | tee "$BUILD/framework-build.log"

FRAMEWORK="$BUILD/Products/Release-appletvos/DexAetherBridge.framework"
test -s "$FRAMEWORK/DexAetherBridge"
file "$FRAMEWORK/DexAetherBridge"
xcrun nm -gU "$FRAMEWORK/DexAetherBridge" > "$BUILD/exported-symbols.txt"
if grep -Eq ' [A-Z] _av(codec|format|util|_)[A-Za-z_0-9]*$' "$BUILD/exported-symbols.txt"; then
  echo "FFmpeg symbols are exported; stop before Kodi integration."
  exit 1
fi
grep 'DexAetherBridge' "$BUILD/exported-symbols.txt"
for API in startEmbedded snapshotForToken command; do
  grep -q "$API" "$BUILD/exported-symbols.txt" || { echo "Missing native bridge API: $API"; exit 1; }
done
# Xcode may omit custom INFOPLIST_KEY settings for generated framework plists.
# Stamp the API only after checking the actual compiled exports.
"$PYTHON" - "$FRAMEWORK/Info.plist" "$BASE/ENGINE-RELEASE.json" <<'PY'
import json, plistlib, sys
from pathlib import Path
path = Path(sys.argv[1])
data = plistlib.loads(path.read_bytes())
data['DexHubBridgeAPI'] = 2
release = json.loads(Path(sys.argv[2]).read_text())
data['DexHubBridgeRevision'] = release['bridge_revision']
data['DexHubAetherVersion'] = release['version']
data['DexHubAetherCommit'] = release['commit']
path.write_bytes(plistlib.dumps(data, fmt=plistlib.FMT_BINARY))
PY
echo "Framework API 2 verified. Continuing with Kodi integration."
