#!/usr/bin/env bash
# Build DexAppleUI.framework (the native Apple TV screens) for Apple TV.
# Output: $DEX_WORK/apple-ui-build/Build/Products/Release-appletvos/DexAppleUI.framework
set -euo pipefail
BASE="$(cd "$(dirname "$0")" && pwd)"
WORK="${DEX_WORK:-$HOME/Developer/DexHub-tvOS}"
OUT="$WORK/apple-ui-build"
python3 "$BASE/generate_project.py"
xcodebuild -project "$BASE/DexAppleUI.xcodeproj" -scheme DexAppleUI -configuration Release \
  -sdk appletvos -destination generic/platform=tvOS -derivedDataPath "$OUT" \
  COMPILER_INDEX_STORE_ENABLE=NO build 2>&1 | tee "$WORK/apple-ui-build.log" | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
FRAMEWORK="$OUT/Build/Products/Release-appletvos/DexAppleUI.framework"
test -s "$FRAMEWORK/DexAppleUI"
nm -gU "$FRAMEWORK/DexAppleUI" | grep -q 'OBJC_CLASS_$_DexAppleUI' || { echo "DexAppleUI class not exported"; exit 1; }
echo "$FRAMEWORK"
