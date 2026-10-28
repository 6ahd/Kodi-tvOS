#!/usr/bin/env bash
# Build Dex Hub for Apple TV entirely inside one folder on an external drive.
#
#   bash env/build.sh            # everything, incremental after the first run
#   DEX_ENV=/path bash env/build.sh
#
# The environment (default /Volumes/Backup/DexHub-Env) holds:
#   depends/    Kodi's prebuilt tvOS dependencies and native tools
#   kodi-src/   a clean Kodi 22.0rc1-Piers checkout (the patch is applied here)
#   base/       the released IPA whose other add-ons and fonts are carried over
#   addons/     the Apple TV Dex Hub add-on and skin (tvos/) and the General
#               zips they match (general/); refreshed from Kodi-General
#   build/      every build product and cache (Kodi, Aether bridge, Apple UI)
#   releases/   finished unsigned IPAs, one folder per version
# Nothing is written to the system disk: temporary files and compiler caches
# stay in build/.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
ENV_DIR="${DEX_ENV:-/Volumes/Backup/DexHub-Env}"
GENERAL="${DEX_GENERAL:-/Volumes/Backup/DexHub-v21.61/Kodi-General}"
NATIVE="$ENV_DIR/depends/aarch64-darwin25.6.0-native"
BUILD="$ENV_DIR/build"
KODI_SRC="$ENV_DIR/kodi-src"
KODI_BUILD="$BUILD/kodi"
MINIMUM=26.0
export PATH="$NATIVE/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export TMPDIR="$BUILD/tmp" CLANG_MODULE_CACHE_PATH="$BUILD/module-cache" CCACHE_DIR="$BUILD/ccache"
[ -x /opt/homebrew/opt/m4/bin/m4 ] && export M4=/opt/homebrew/opt/m4/bin/m4
PYTHON="$NATIVE/bin/python3"
mkdir -p "$TMPDIR" "$CLANG_MODULE_CACHE_PATH" "$KODI_BUILD" "$ENV_DIR/releases"
step() { printf '\n== %s ==\n' "$1"; }

step "Checks"
[ -x "$PYTHON" ] || { echo "Kodi depends missing: $ENV_DIR/depends"; exit 1; }
[ -d "$KODI_SRC/.git" ] || git clone --depth 1 --branch 22.0rc1-Piers https://github.com/xbmc/xbmc.git "$KODI_SRC"
BASE_IPA="$(ls "$ENV_DIR"/base/*.ipa | head -1)"
[ -f "$BASE_IPA" ] || { echo "No released IPA in $ENV_DIR/base"; exit 1; }
[ -f "$KODI_SRC/tools/depends/Makefile.include" ] || cp "$ENV_DIR/depends/Makefile.include.kodi" "$KODI_SRC/tools/depends/Makefile.include"
df -h "$ENV_DIR" | tail -1

step "Kodi source: DexHub patch and artwork"
"$PYTHON" "$REPO/apply_kodi_patch.py" "$KODI_SRC"
xcrun swift -module-cache-path "$CLANG_MODULE_CACHE_PATH" "$REPO/branding/render_branding.swift" "$BUILD/branding" >/dev/null
"$PYTHON" "$REPO/branding/install_branding.py" "$KODI_SRC" "$BUILD/branding"

step "Kodi (Release, appletvos)"
"$PYTHON" "$REPO/prepare_toolchain.py" "$KODI_SRC" "$KODI_BUILD" "$MINIMUM" >/dev/null
if [ ! -f "$KODI_BUILD/CMakeCache.txt" ]; then
  make -C "$KODI_SRC/tools/depends/target/cmakebuildsys" BUILD_DIR="$KODI_BUILD" \
    CMAKE_EXTRA_ARGUMENTS="-DCMAKE_TOOLCHAIN_FILE=\"$KODI_BUILD/DexHubToolchain.cmake\"" > "$BUILD/kodi-configure.log" 2>&1
else
  (cd "$KODI_BUILD" && cmake . > "$BUILD/kodi-configure.log" 2>&1)
fi
(cd "$KODI_BUILD" && xcodebuild -target kodi -configuration Release -jobs "$(sysctl -n hw.ncpu)" \
  TVOS_DEPLOYMENT_TARGET="$MINIMUM" MODULE_CACHE_DIR="$CLANG_MODULE_CACHE_PATH" COMPILER_INDEX_STORE_ENABLE=NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build > "$BUILD/kodi-build.log" 2>&1) \
  || { grep -E " error:" "$BUILD/kodi-build.log" | sort -u | head -20; echo "Kodi build failed: $BUILD/kodi-build.log"; exit 1; }
KODI_APP="$KODI_BUILD/build/Release-appletvos/Kodi.app"
test -x "$KODI_APP/Kodi"
echo "$KODI_APP"

step "Aether bridge"
ENGINE="$("$PYTHON" "$REPO/prepare_aether.py" "$BUILD")"
"$PYTHON" "$REPO/generate_project.py" "$ENGINE" >/dev/null
xcodebuild -project "$REPO/DexAetherBridge.xcodeproj" -scheme DexAetherBridge -configuration Release \
  -sdk appletvos -destination generic/platform=tvOS -derivedDataPath "$BUILD/bridge" \
  -clonedSourcePackagesDirPath "$BUILD/bridge-packages" -packageCachePath "$BUILD/bridge-cache" \
  TVOS_DEPLOYMENT_TARGET="$MINIMUM" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO COMPILER_INDEX_STORE_ENABLE=NO \
  build > "$BUILD/bridge-build.log" 2>&1 \
  || { grep -E " error:" "$BUILD/bridge-build.log" | sort -u | head -20; echo "Bridge build failed"; exit 1; }
BRIDGE_PRODUCTS="$BUILD/bridge/Build/Products/Release-appletvos"
nm -gU "$BRIDGE_PRODUCTS/DexAetherBridge.framework/DexAetherBridge" | grep -q snapshotForToken

step "Dex Hub add-on and skin from General"
# Every build starts from the newest general release (the General folder is
# where new versions land); its changes are merged into the Apple TV copies.
"$PYTHON" "$REPO/tools/sync_from_general.py" "$GENERAL" "$ENV_DIR/addons"
ADDONS="$BUILD/addons"
rm -rf "$ADDONS" && mkdir -p "$ADDONS"
cp -R "$ENV_DIR"/addons/tvos/* "$ADDONS/"
cp -R "$REPO/script.dexhub.tvos.players" "$ADDONS/"

step "Package"
VERSION="$("$PYTHON" -c 'import json,sys; print(json.load(open(sys.argv[1]))["app_version"])' "$REPO/ENGINE-RELEASE.json")"
OUT="$ENV_DIR/releases/v$VERSION"
mkdir -p "$OUT"
"$PYTHON" "$REPO/repackage_release.py" "$BASE_IPA" "$KODI_APP" "$BRIDGE_PRODUCTS" "$OUT" "$ADDONS" | tail -1
IPA="$(ls -t "$OUT"/*.ipa | head -1)"
"$PYTHON" "$REPO/env/verify_ipa.py" "$IPA" "$BASE_IPA" "$ADDONS"
(cd "$OUT" && shasum -a 256 "$(basename "$IPA")" > SHA256SUMS.txt)
echo
echo "$IPA"
