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
CONFIG="${DEX_CONFIG:-Release}"
case "$CONFIG" in Release|Debug) ;; *) echo "DEX_CONFIG must be Release or Debug"; exit 1 ;; esac
FRAMEWORK="$WORK/aether-bridge-build/Products/Release-appletvos/DexAetherBridge.framework"
test -s "$FRAMEWORK/DexAetherBridge"
"$PYTHON" - "$FRAMEWORK/Info.plist" "$BASE/ENGINE-RELEASE.json" <<'PY'
import json, plistlib, sys
from pathlib import Path
p = plistlib.loads(Path(sys.argv[1]).read_bytes())
r = json.loads(Path(sys.argv[2]).read_text())
if not (p.get('DexHubBridgeAPI') == 2 and p.get('DexHubBridgeRevision') == r['bridge_revision']
        and p.get('DexHubAetherVersion') == r['version'] and p.get('DexHubAetherCommit') == r['commit']):
    raise SystemExit('Old Swift bridge: run all.sh before packaging.')
PY
MINIMUM="$(cat "$WORK/aether-bridge-build/deployment.txt")"
echo "Experimental IPA will require tvOS $MINIMUM or newer."
KODI_SRC="${KODI_SRC:-$WORK/kodi-rc1-source}"
KODI_BUILD="${KODI_BUILD:-$WORK/kodi-tvos17-build}"
"$PYTHON" "$BASE/apply_kodi_patch.py" "$KODI_SRC"
# DexHub app icon, top shelf, launch image and splash (drawn, not stored as PNGs)
xcrun swift "$BASE/branding/render_branding.swift" "$WORK/branding"
"$PYTHON" "$BASE/branding/install_branding.py" "$KODI_SRC" "$WORK/branding"
git -C "$KODI_SRC" diff --check
if [ -x /opt/homebrew/opt/m4/bin/m4 ]; then export M4=/opt/homebrew/opt/m4/bin/m4; fi
"$PYTHON" "$BASE/prepare_toolchain.py" "$KODI_SRC" "$KODI_BUILD" "$MINIMUM"
make -C "$KODI_SRC/tools/depends/target/cmakebuildsys" BUILD_DIR="$KODI_BUILD" \
  CMAKE_EXTRA_ARGUMENTS="-DCMAKE_TOOLCHAIN_FILE=\"$KODI_BUILD/DexHubToolchain.cmake\""
cd "$KODI_BUILD"
xcodebuild -target kodi -configuration "$CONFIG" -jobs "$(sysctl -n hw.ncpu)" \
  TVOS_DEPLOYMENT_TARGET="$MINIMUM" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build 2>&1 | tee "$WORK/aether-bridge-build/kodi-bridge-build.log"

STAGE="$(mktemp -d "$WORK/aether-ipa-stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/Payload/Kodi.app"
mkdir -p "$STAGE/Payload"
ditto "$KODI_BUILD/build/$CONFIG-appletvos/Kodi.app" "$APP"
ditto "$FRAMEWORK" "$APP/Frameworks/DexAetherBridge.framework"
# Swift remote navigation, loaded at run time by LibInputTouch.mm (built-in
# gesture handling is used when it is missing). Prebuilt; see vendor/README.md.
ditto "$BASE/vendor/DexNavigationKit.framework" "$APP/Frameworks/DexNavigationKit.framework"
# Native Apple TV screens over Kodi (apple-ui/); Kodi alone opens without them.
DEX_WORK="$WORK" bash "$BASE/apple-ui/build.sh"
ditto "$WORK/apple-ui-build/Build/Products/Release-appletvos/DexAppleUI.framework" "$APP/Frameworks/DexAppleUI.framework"
# v21.36: Aether's resource bundle. AetherEngine 7.38 loads silent-atmos.mp4
# from Bundle.module (AetherEngine_AetherEngine.bundle) when Atmos or DTS:X
# plays as APAC; Xcode leaves the bundle beside the framework, not inside the
# app, and Kodi stopped with a trap the moment such a title started.
AE_BUNDLE="AetherEngine_AetherEngine.bundle"
AE_BUILT="$(find "$WORK/aether-bridge-build/Products" "$WORK/aether-bridge-build/Intermediates" -type d -name "$AE_BUNDLE" 2>/dev/null | while read -r B; do [ -f "$B/silent-atmos.mp4" ] && echo "$B"; done | head -1 || true)"
rm -rf "$APP/$AE_BUNDLE"
if [ -n "$AE_BUILT" ]; then
  ditto "$AE_BUILT" "$APP/$AE_BUNDLE"
else
  AE_MP4="$(find "$WORK" -path '*Sources/AetherEngine/Resources/silent-atmos.mp4' -type f 2>/dev/null | head -1 || true)"
  [ -n "$AE_MP4" ] || { echo "Aether resource silent-atmos.mp4 not found: stop before shipping an app that stops on Atmos."; exit 1; }
  mkdir -p "$APP/$AE_BUNDLE"
  cp "$AE_MP4" "$APP/$AE_BUNDLE/silent-atmos.mp4"
  "$PYTHON" - "$APP/$AE_BUNDLE/Info.plist" <<'PY'
import plistlib, sys
plistlib.dump({'CFBundleIdentifier': 'AetherEngine-AetherEngine-resources', 'CFBundleName': 'AetherEngine_AetherEngine',
               'CFBundlePackageType': 'BNDL', 'CFBundleInfoDictionaryVersion': '6.0', 'CFBundleShortVersionString': '1.0',
               'CFBundleVersion': '1', 'CFBundleSupportedPlatforms': ['AppleTVOS'], 'MinimumOSVersion': '18.0'},
              open(sys.argv[1], 'wb'))
PY
fi
test -s "$APP/$AE_BUNDLE/silent-atmos.mp4" || { echo "Missing $AE_BUNDLE in the app."; exit 1; }
echo "Aether resources: $APP/$AE_BUNDLE"

# The resolved graph contains the reviewed binary slices. Copy these rather
# than stale products left by an earlier build of the bridge.
"$PYTHON" "$BASE/package_frameworks.py" "$WORK/aether-bridge-build/SourcePackages" "$APP"
# v21.31: DTSX.framework is LGPL; its NOTICE and licences travel with the app
DTSX_SRC="$(find "$WORK/aether-bridge-build/SourcePackages/checkouts" -maxdepth 1 -iname 'LibDTSX' | head -1)"
if [ -n "$DTSX_SRC" ] && [ -d "$APP/Frameworks/DTSX.framework" ]; then
  mkdir -p "$APP/Licenses/LibDTSX"
  cp "$DTSX_SRC/NOTICE" "$DTSX_SRC/LICENSE" "$APP/Licenses/LibDTSX/"
  cp -R "$DTSX_SRC/LICENSES" "$APP/Licenses/LibDTSX/"
fi
cp "$BASE/licenses/"*.txt "$APP/Licenses/" 2>/dev/null || true
# v21.3: rebuild the Dex Hub, skin and player ZIPs from src/ first. Before this,
# assets/ kept the ZIPs of the last manual release_assets.py run, so a build
# shipped an old Dex Hub even when src/ was newer.
"$PYTHON" "$BASE/release_assets.py"
"$PYTHON" "$BASE/package_assets.py" "$BASE" "$APP" "$MINIMUM"
xcrun swift-stdlib-tool --copy --platform appletvos \
  --scan-executable "$APP/Frameworks/DexAetherBridge.framework/DexAetherBridge" \
  --scan-folder "$APP/Frameworks" --destination "$APP/Frameworks"
bash "$BASE/normalize_frameworks.sh" "$APP"

APP_VERSION="$("$PYTHON" -c 'import json,sys; print(json.load(open(sys.argv[1]))["app_version"])' "$BASE/ENGINE-RELEASE.json")"
OUT="${DEX_OUTPUT_DIR:-$HOME/Downloads}/Kodi-DexHub-v$APP_VERSION-unsigned-$(date +%Y%m%d-%H%M%S).ipa"
ditto -c -k --keepParent "$STAGE/Payload" "$OUT"
unzip -t "$OUT" >/dev/null
for ASSET in "$BASE"/assets/*.zip; do
  ditto "$ASSET" "${DEX_OUTPUT_DIR:-$HOME/Downloads}/$(basename "$ASSET")"
done
echo "$OUT"
echo "Sign the entire IPA, including embedded frameworks, before installing."
if [ "${DEX_SHOW_OUTPUT:-1}" = 1 ]; then open -R "$OUT"; fi
