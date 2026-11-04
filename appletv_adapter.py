"""v21.43: Apple TV system features, planned before the caller writes any file.

Picture in Picture, Top Shelf rows from Dex Hub, chapters (in TVOSAetherPlayer)
and Apple TV user -> Kodi profile. Every change is anchored and idempotent.
"""
import plistlib

FOLDER = 'xbmc/platform/darwin/tvos/'
SCENE_MARKER = '// DexHub Scene Lifecycle for Kodi built with modern tvOS SDKs.'
SCENE_END = 'static void SigPipeHandler(int s)'
RUN_TOP_SHELF = '''  m_handleUrl = false;
  std::vector<std::string> split = StringUtils::Split(m_url, "/");
  std::string url = Base64::Decode(split[4]);'''
RUN_TOP_SHELF_DEX = '''  m_handleUrl = false;
  std::vector<std::string> split = StringUtils::Split(m_url, "/");
  // DexHub Top Shelf v21.43: Dex Hub cards carry an id the app looks up.
  if (split.size() >= 5 && split[3] == "dexhub")
  {
    DexHubRunTopShelfItem(split[2], split[4]);
    return;
  }
  if (split.size() < 5)
    return;
  // Base64 may itself hold '/'.
  std::string encoded = split[4];
  for (size_t index = 5; index < split.size(); ++index)
    encoded += "/" + split[index];
  std::string url = Base64::Decode(encoded);'''
BUILTINS = ('#if defined(TARGET_DARWIN_TVOS)\n'
            '          {"dexhub.pictureinpicture", {"Toggle Picture in Picture", 0, DexHubPictureInPicture}},\n'
            '          {"dexhub.topshelf", {"Publish the Dex Hub Top Shelf", 0, DexHubTopShelf}},\n'
            '          {"dexhub.appletvuser", {"Link Apple TV users to Kodi profiles", 0, DexHubAppleTVUser}},\n'
            '#endif\n')


def plan_appletv(root, base, planned, replace_one):
    def read(name):
        if name in planned:
            return planned[name]
        path = root / name
        if not path.is_file():
            raise SystemExit('Unsupported/incomplete Kodi source: ' + name)
        return path.read_text()

    # New native sources, owned by this repository.
    for name in ('TVOSDexHubSystem.h', 'TVOSDexHubSystem.mm'):
        planned[FOLDER + name] = (base / 'native' / name).read_text()
    relative = FOLDER + 'CMakeLists.txt'
    text = read(relative)
    for section, filename in [('SOURCES', 'TVOSDexHubSystem.mm'), ('HEADERS', 'TVOSDexHubSystem.h')]:
        if filename not in text:
            anchor = 'set(' + section + ' '
            text = replace_one(text, anchor, anchor + filename + '\n            ', relative)
    planned[relative] = text

    # Builtins for the skin and add-ons.
    relative = 'xbmc/interfaces/builtins/SystemBuiltins.cpp'
    text = read(relative)
    if 'TVOSDexHubSystem.h' not in text:
        anchor = '#include "platform/darwin/tvos/TVOSExternalApp.h"'
        text = replace_one(text, anchor, anchor + '\n#include "platform/darwin/tvos/TVOSDexHubSystem.h"', relative)
        anchor = '          {"activatescreensaver",'
        text = replace_one(text, anchor, BUILTINS + anchor, relative)
    planned[relative] = text

    # Top Shelf: the provider reads Dex Hub rows as well as Kodi's library rows.
    shelf = FOLDER + 'TopShelf/'
    read(shelf + 'ServiceProvider.mm')
    planned[shelf + 'ServiceProvider.h'] = (base / 'native/TopShelfProvider.h').read_text()
    planned[shelf + 'ServiceProvider.mm'] = (base / 'native/TopShelfProvider.mm').read_text()
    relative = shelf + 'Info.plist.in'
    info = plistlib.loads(read(relative).encode())
    extension = info.get('NSExtension') or {}
    if extension.get('NSExtensionPointIdentifier') != 'com.apple.tv-top-shelf':
        extension.pop('NSExtensionAttributes', None)
        extension['NSExtensionPointIdentifier'] = 'com.apple.tv-top-shelf'
        extension['NSExtensionPrincipalClass'] = 'ServiceProvider'
        info['NSExtension'] = extension
        planned[relative] = plistlib.dumps(info, sort_keys=False).decode()

    relative = FOLDER + 'TVOSTopShelf.mm'
    text = read(relative)
    if '// DexHub Top Shelf v21.43' not in text:
        text = replace_one(text, RUN_TOP_SHELF, RUN_TOP_SHELF_DEX, relative)
        text = replace_one(text, '#import "TVOSTopShelf.h"\n',
                           '#import "TVOSTopShelf.h"\n#include "TVOSDexHubSystem.h"\n', relative)
    planned[relative] = text

    # Picture in Picture keeps playing outside the app: tvOS needs the audio mode.
    relative = FOLDER + 'Info.plist.in'
    info = plistlib.loads(read(relative).encode())
    modes = list(info.get('UIBackgroundModes') or [])
    if 'audio' not in modes:
        info['UIBackgroundModes'] = modes + ['audio']
        planned[relative] = plistlib.dumps(info, sort_keys=False).decode()

    # The scene delegate (apply_bridge.py inserts it once): upgrade an older copy.
    relative = FOLDER + 'XBMCApplication.mm'
    text = read(relative)
    scene = (base / 'native/scene-lifecycle.txt').read_text()
    if SCENE_MARKER in text and scene not in text:
        start = text.index(SCENE_MARKER)
        end = text.index(SCENE_END, start)
        text = text[:start] + scene + text[end:]
    planned[relative] = text
