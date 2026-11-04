#!/usr/bin/env bash
# v21.43: pack the Dex Hub skin's images into media/Textures.xbt, as Kodi does for
# its own skins. Kodi then reads ready textures from one file instead of opening and
# decoding ~2,000 PNGs as the menus need them. Kodi looks in the bundle first for an
# image the skin names by a media path; the loose files stay for images an add-on
# opens by full path (special://skin/media/...). An update of the skin from the
# repository replaces the whole skin folder, so no older bundle is left behind.
# Usage: pack_textures.sh <Kodi.app> <TexturePacker>
set -euo pipefail
APP="$1"
PACKER="${2:-}"
SKIN="$APP/AppData/AppHome/addons/skin.dexhub.tvos"
[ -d "$SKIN/media" ] || { echo "Skin media not found in $APP"; exit 1; }
if [ -z "$PACKER" ] || [ ! -x "$PACKER" ]; then
  echo "TexturePacker not found: the skin's images stay loose (slower to load)."
  exit 0
fi
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
# Images only, in their folders (the bundle keeps the paths the skin uses).
(cd "$SKIN/media" && find . -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.gif' \) \
  -not -path './Textures.xbt' -print | cpio -pdm "$STAGE" 2>/dev/null)
COUNT="$(find "$STAGE" -type f | wc -l | tr -d ' ')"
rm -f "$SKIN/media/Textures.xbt"
"$PACKER" -input "$STAGE" -output "$SKIN/media/Textures.xbt" -dupecheck >/dev/null
test -s "$SKIN/media/Textures.xbt" || { echo "TexturePacker wrote no Textures.xbt"; exit 1; }
echo "Skin textures packed: $COUNT images, $(du -h "$SKIN/media/Textures.xbt" | cut -f1) Textures.xbt"
