#!/usr/bin/env python3
"""Validated, repeatable source adapter. No checkout/reset or dependency changes."""
import argparse
import hashlib
import json
import plistlib
from datetime import datetime, timezone
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('source', type=Path)
parser.add_argument('--check', action='store_true')
parser.add_argument('--restore', type=Path)
args = parser.parse_args()
root = args.source.resolve()
base = Path(__file__).resolve().parent
sha = lambda data: hashlib.sha256(data).hexdigest()
if args.restore:
    backup = args.restore.resolve()
    manifest = json.loads((backup / 'manifest.json').read_text())
    if manifest['source'] != str(root):
        raise SystemExit('Backup belongs to another source checkout')
    for entry in manifest['files']:
        path = root / entry['path']
        if not path.is_file() or sha(path.read_bytes()) != entry['after']:
            raise SystemExit('Source changed since patch; restore stopped: ' + entry['path'])
    for entry in manifest['files']:
        path = root / entry['path']
        if entry['existed']:
            path.write_bytes((backup / entry['path']).read_bytes())
        else:
            path.unlink()
    print('Restored the source changes from', backup)
    raise SystemExit(0)

planned = {}
def read(relative):
    path = root / relative
    if not path.is_file():
        raise SystemExit('Unsupported/incomplete Kodi source: ' + relative)
    return path.read_text()
def replace_one(text, old, new, relative):
    if text.count(old) != 1:
        raise SystemExit('Compatibility check failed; no source files changed: ' + relative)
    return text.replace(old, new, 1)

folder = 'xbmc/platform/darwin/tvos/'
relative = folder + 'TVOSExternalApp.mm'
path = root / relative
if path.exists():
    text = path.read_text()
    anchor = '  // openURL must run on the main thread'
    for marker in ('  // DexAetherBridge experimental handoff.', '  // DexAetherBridge managed handoff v2.'):
        if marker in text:
            start = text.index(marker)
            end = text.index(anchor, start)
            text = text[:start] + text[end:]
    block = (base / 'native/bridge-block.txt').read_text()
    text = replace_one(text, anchor, block + anchor, relative)
    if '#include "ServiceBroker.h"' not in text:
        text = replace_one(text, '#import "utils/log.h"', '#import "utils/log.h"\n#include "ServiceBroker.h"\n#include "messaging/ApplicationMessenger.h"', relative)
    planned[relative] = text
else:
    planned[relative] = (base / 'native/TVOSExternalApp.mm').read_text()
header = folder + 'TVOSExternalApp.h'
if not (root / header).exists():
    planned[header] = (base / 'native/TVOSExternalApp.h').read_text()
relative = folder + 'CMakeLists.txt'
text = read(relative)
for section, filename in [('SOURCES', 'TVOSExternalApp.mm'), ('HEADERS', 'TVOSExternalApp.h')]:
    if filename not in text:
        anchor = 'set(' + section + ' '
        text = replace_one(text, anchor, anchor + filename + '\n            ', relative)
planned[relative] = text
relative = 'xbmc/interfaces/builtins/SystemBuiltins.cpp'
text = read(relative)
if '"system.openurl"' in text and 'CTVOSExternalApp::OpenURL' not in text:
    raise SystemExit('Existing System.OpenURL implementation differs; no source files changed')
if '"system.openurl"' not in text:
    text = replace_one(text, '#include "SystemBuiltins.h"', '#include "SystemBuiltins.h"\n\n#if defined(TARGET_DARWIN_TVOS)\n#include "platform/darwin/tvos/TVOSExternalApp.h"\n#endif', relative)
    anchor = 'CBuiltins::CommandMap CSystemBuiltins::GetOperations() const'
    text = replace_one(text, anchor, 'static int DexHubOpenURL(const std::vector<std::string>& params)\n{\n#if defined(TARGET_DARWIN_TVOS)\n  if (!params.empty())\n    return CTVOSExternalApp::OpenURL(params[0]) ? 0 : -1;\n#endif\n  return -1;\n}\n\n' + anchor, relative)
    text = replace_one(text, 'return {{"activatescreensaver",', 'return {{"system.openurl", {"Open a tvOS app or DexHub player", 1, DexHubOpenURL}},\n          {"activatescreensaver",', relative)
planned[relative] = text
# Give only buttons declaring onlongclick a Context Menu/long-select action.
relative = 'xbmc/guilib/GUIButtonControl.h'
text = read(relative)
if 'm_dexLongClickActions' not in text:
    text = replace_one(text, '  CGUIAction m_clickActions;', '  CGUIAction m_clickActions;\n  CGUIAction m_dexLongClickActions;', relative)
    anchor = '  void SetClickActions(const CGUIAction& clickActions) { m_clickActions = clickActions; }'
    text = replace_one(text, anchor, anchor + '\n  void SetDexLongClickActions(const CGUIAction& actions) { m_dexLongClickActions = actions; }', relative)
planned[relative] = text
relative = 'xbmc/guilib/GUIButtonControl.cpp'
text = read(relative)
if 'm_dexLongClickActions(control.m_dexLongClickActions)' not in text:
    text = replace_one(text, '    m_clickActions(control.m_clickActions),', '    m_clickActions(control.m_clickActions),\n    m_dexLongClickActions(control.m_dexLongClickActions),', relative)
    anchor = '  if (action.GetID() == ACTION_SELECT_ITEM)'
    text = replace_one(text, anchor, '  if (action.GetID() == ACTION_CONTEXT_MENU && m_dexLongClickActions.HasActionsMeetingCondition())\n  {\n    m_dexLongClickActions.ExecuteActions(GetID(), GetParentID());\n    return true;\n  }\n' + anchor, relative)
planned[relative] = text
relative = 'xbmc/guilib/GUIControlFactory.cpp'
text = read(relative)
if 'SetDexLongClickActions' not in text:
    anchor = '      bcontrol->SetClickActions(clickActions);'
    text = replace_one(text, anchor, anchor + '\n      CGUIAction dexLongClickActions;\n      GetActions(pControlNode, "onlongclick", dexLongClickActions);\n      bcontrol->SetDexLongClickActions(dexLongClickActions);', relative)
planned[relative] = text
# UIKit requires scene lifecycle for apps linked with newer SDKs.
relative = folder + 'input/LibInputTouch.mm'
text = read(relative)
marker = '// DexHub: Back stays in Kodi so Home can confirm exit.'
if marker not in text:
    anchor = '''      const auto& components = CServiceBroker::GetAppComponents();
      const auto appPlayer = components.GetComponent<CApplicationPlayer>();
      // menu is special.
      //  a) if at our home view, should return to atv home screen.
      //  b) if not, let it pass to us.
      if (CServiceBroker::GetGUI()->GetWindowManager().GetActiveWindow() == WINDOW_HOME &&
          !CServiceBroker::GetGUI()->GetWindowManager().HasVisibleModalDialog() &&
          !appPlayer->IsPlaying())
        handled = NO;'''
    text = replace_one(text, anchor, '      ' + marker + '\n      handled = YES;', relative)
planned[relative] = text

relative = folder + 'Info.plist.in'
info_text = read(relative)
info = plistlib.loads(info_text.encode())
manifest = info.get('UIApplicationSceneManifest')
if not manifest:
    application = folder + 'XBMCApplication.mm'
    text = read(application)
    marker = '// DexHub Scene Lifecycle for Kodi built with modern tvOS SDKs.'
    if marker not in text:
        startup = ('  self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];\n'
                   '  self.window.rootViewController = [XBMCController new];\n'
                   '  [self.window makeKeyAndVisible];\n'
                   '  [self.xbmcController startAnimation];')
        text = replace_one(text, startup,
                           '  // The scene delegate creates the Kodi window.', application)
        anchor = 'static void SigPipeHandler(int s)'
        text = replace_one(text, anchor,
                           (base / 'native/scene-lifecycle.txt').read_text() + anchor, application)
        anchor = '  NSString* action = urlComponents[2];'
        text = replace_one(text, anchor, '  if (urlComponents.count < 3)\n    return NO;\n' + anchor, application)
    planned[application] = text
    info['UIApplicationSceneManifest'] = {
        'UIApplicationSupportsMultipleScenes': False,
        'UISceneConfigurations': {
            'UIWindowSceneSessionRoleApplication': [{
                'UISceneConfigurationName': 'DexHub Kodi',
                'UISceneClassName': 'UIWindowScene',
                'UISceneDelegateClassName': 'DexHubSceneDelegate',
            }]
        }
    }
    planned[relative] = plistlib.dumps(info, sort_keys=False).decode()
else:
    print('Existing scene lifecycle declaration preserved')

# Receive callbacks through both scene forwarding and the app delegate.
relative = folder + 'TVOSExternalApp.mm'
text = planned[relative]
if 'bool CTVOSExternalApp::HandleURL(' not in text:
    text += (base / 'native/infuse-return.txt').read_text()
if '#include "platform/darwin/tvos/filesystem/TVOSFileUtils.h"' not in text:
    text = replace_one(text, '#import "TVOSExternalApp.h"', '#import "TVOSExternalApp.h"\n#include "platform/darwin/tvos/filesystem/TVOSFileUtils.h"', relative)
planned[relative] = text
relative = header
text = planned.get(relative) or read(relative)
if 'static bool HandleURL(' not in text:
    text = replace_one(text, '  static bool OpenURL(const std::string& url);', '  static bool OpenURL(const std::string& url);\n  static bool HandleURL(const std::string& url);', relative)
planned[relative] = text
relative = folder + 'XBMCApplication.mm'
text = planned.get(relative) or read(relative)
if 'CTVOSExternalApp::HandleURL(' not in text:
    anchor = '  NSArray* urlComponents = [url.absoluteString componentsSeparatedByString:@"/"];'
    text = replace_one(text, anchor, '  if (CTVOSExternalApp::HandleURL(url.absoluteString.UTF8String))\n    return YES;\n' + anchor, relative)
    text = '#include "platform/darwin/tvos/TVOSExternalApp.h"\n' + text
planned[relative] = text
relative = folder + 'Info.plist.in'
info = plistlib.loads((planned.get(relative) or read(relative)).encode())
schemes = [scheme for entry in info.get('CFBundleURLTypes', []) for scheme in entry.get('CFBundleURLSchemes', [])]
if 'dexhub-player' not in schemes:
    info.setdefault('CFBundleURLTypes', []).append({'CFBundleURLName': 'DexHub Infuse return', 'CFBundleURLSchemes': ['dexhub-player']})
    planned[relative] = plistlib.dumps(info, sort_keys=False).decode()

from native_player_adapter import plan_native
plan_native(root, base, planned, replace_one)
from appletv_adapter import plan_appletv
plan_appletv(root, base, planned, replace_one)

changes = [(name, text) for name, text in planned.items() if not (root/name).exists() or (root/name).read_text() != text]
print('Compatible source:', root)
print('Source files to change:', len(changes))
if args.check or not changes:
    raise SystemExit(0)
backup = root / '.dexhub-backups' / datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S-%f')
backup.mkdir(parents=True)
manifest = {'source': str(root), 'files': []}
for name, text in changes:
    path = root/name
    existed = path.exists()
    if existed:
        saved = backup/name
        saved.parent.mkdir(parents=True, exist_ok=True)
        saved.write_bytes(path.read_bytes())
    manifest['files'].append({'path': name, 'existed': existed, 'after': sha(text.encode())})
(backup/'manifest.json').write_text(json.dumps(manifest, indent=2))
try:
    for name, text in changes:
        (root/name).write_text(text)
except Exception:
    for entry in manifest['files']:
        path = root/entry['path']
        if entry['existed']:
            path.write_bytes((backup/entry['path']).read_bytes())
        elif path.exists():
            path.unlink()
    raise
print('Backup:', backup)
