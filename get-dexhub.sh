#!/usr/bin/env bash
# Download missing Apple TV add-on/skin assets from the configured update source.
set -euo pipefail
BASE="$(cd "$(dirname "$0")" && pwd)"
REPO_URL="${DEX_REPO_URL:-https://dexworld.cc/appletv/}"
REPO_URL="${REPO_URL%/}/"
if ls "$BASE"/assets/plugin.video.dexhub.tvos-*.zip >/dev/null 2>&1 && ls "$BASE"/assets/skin.dexhub.tvos-*.zip >/dev/null 2>&1; then
  echo "Dex Hub add-on and skin already in assets/."
  exit 0
fi
INDEX="$(mktemp)"
trap 'rm -f "$INDEX"' EXIT
curl -fsSL --retry 3 "$REPO_URL"addons.xml -o "$INDEX"
URLS="$(python3 - "$INDEX" "$REPO_URL" <<'PY'
import sys
import xml.etree.ElementTree as ET
from urllib.parse import urlsplit
url = sys.argv[2]
if urlsplit(url).scheme not in ('https', 'http') or not urlsplit(url).netloc:
    raise SystemExit('Invalid repository URL')
addons = {row.get('id'): row.get('version') for row in ET.parse(sys.argv[1]).getroot()}
for identifier in ('plugin.video.dexhub.tvos', 'skin.dexhub.tvos'):
    version = addons[identifier]
    if not version or any(c not in '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.+-' for c in version):
        raise SystemExit('Invalid repository add-on version')
    print(url + identifier + '/' + identifier + '-' + version + '.zip')
PY
)"
for URL in $URLS; do
  FILE="$BASE/assets/$(basename "$URL")"
  curl -fLsS --retry 3 -o "$FILE.tmp" "$URL"
  unzip -t "$FILE.tmp" >/dev/null
  mv "$FILE.tmp" "$FILE"
done
