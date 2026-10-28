import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

# Usage: test_source_update.py CLEAN_KODI_22.0rc1-Piers_CHECKOUT (left clean afterwards)
base=Path(__file__).resolve().parents[1]
source=Path(sys.argv[1]).resolve()
before_diff=subprocess.run(['git','-C',str(source),'diff'],capture_output=True,check=True).stdout
def run(*args):
    return subprocess.run([sys.executable,str(base/'apply_kodi_patch.py'),str(source),*args],check=True,capture_output=True,text=True).stdout
assert 'applies' in run('--check')
run()
assert 'already applied' in run('--check')
assert 'already applied' in run()
subprocess.run(['git','-C',str(source),'diff','--check'],check=True)
text=(source/'xbmc/ServiceManager.cpp').read_text()
stage=text.split('bool CServiceManager::InitStageTwo',1)[1].split('bool CServiceManager::InitStageThree',1)[0]
assert stage.index('PrepareDexHubBundle();')<stage.index('m_addonMgr->Init()')<stage.index('ActivateDexHubBundle(*m_addonMgr);')
assert stage.index('ActivateDexHubBundle(*m_addonMgr);')<stage.index('m_serviceAddons =')
application=(source/'xbmc/application/Application.cpp').read_text()
assert application.index('m_pGUI->Init();') < application.index('ConfigureDexHubSkin();') < application.index('std::string skinId = settings->GetString(CSettings::SETTING_LOOKANDFEEL_SKIN);')
setup=(source/'xbmc/platform/darwin/tvos/TVOSDexHubSetup.mm').read_text()
activate=setup.split('void ActivateDexHubBundle',1)[1].split('void ConfigureDexHubSkin',1)[0]
assert 'SetString(' not in activate and 'SetInt(' not in activate
configure=setup.split('void ConfigureDexHubSkin',1)[1]
assert configure.index('!CServiceBroker::GetGUI()') < configure.index('settings->SetString(')
assert '@"DexHubDefaultSkinConfigured-v13"' in configure
setting=ET.parse(source/'system/settings/darwin_tvos.xml').find('.//setting[@id="videoplayer.dexhubnativeversion"]')
assert setting.findtext('level')=='4' and setting.findtext('visible')!='false'
zip_builtin=(source/'xbmc/interfaces/builtins/AddonBuiltins.cpp').read_text()
assert 'SETTING_ADDONS_ALLOW_UNKNOWN_SOURCES' in zip_builtin and 'file.parent_path() != imports' in zip_builtin
for filename in ['xbmc/cores/playercorefactory/PlayerCoreFactory.cpp','xbmc/cores/playercorefactory/PlayerCoreConfig.cpp','xbmc/application/ApplicationPlayer.cpp']:
    content=(source/filename).read_text()
    assert 'KSPlayer' not in content and 'MPV' not in content
    assert 'Aether' in content
native=(source/'xbmc/platform/darwin/tvos/TVOSAetherPlayer.mm').read_text()
assert native.count('Class bridge = Bridge(')==3
assert '[Bridge(engineName, false) command:request]' in native
assert 'DexKSBridge' not in native and 'DexMPVBridge' not in native
engine=ET.parse(source/'system/settings/darwin_tvos.xml').find('.//setting[@id="videoplayer.dexhubengine"]')
assert engine.findtext('level') == '0' and engine.findtext('default') == '1'
assert [x.text for x in engine.findall('./constraints/options/option')] == ['0','1','2']
assert ET.parse(source/'system/settings/darwin_tvos.xml').find('.//setting[@id="videoplayer.dexhubtruehdatmos"]') is not None
setter=native.split('void CTVOSAetherPlayer::SetSubtitleVerticalPosition',1)[1].split('void CTVOSAetherPlayer::GetAudioCapabilities',1)[0]
assert 'm_lock' not in setter
# v21.62: Back on the Home window leaves for the Apple TV Home screen; Now Playing identity.
touch=(source/'xbmc/platform/darwin/tvos/input/LibInputTouch.mm').read_text()
menu=touch.split('case UIPressTypeMenu:',1)[1].split('break;',1)[0]
assert 'WINDOW_HOME' in menu and 'handled = NO;' in menu and '"dexhub.keepback"' in menu
assert 'request[@"nowPlaying"] = nowPlaying;' in native and 'm_callback.OnPlayBackPaused();' in native
# v21.70: native Apple TV screens over Kodi, Back from Kodi's Home, DexHub.AppleMode.
apple=(source/'xbmc/platform/darwin/tvos/TVOSAppleMode.mm').read_text()
assert 'JSONRPC::CJSONRPC::MethodCall' in apple and 'DexAppleUI.framework' in apple
assert 'CTVOSAppleMode::HandleBackFromKodi()' in touch and 'CTVOSAppleMode::Start();' in (source/'xbmc/platform/darwin/tvos/XBMCController.mm').read_text()
assert '"dexhub.applemode"' in (source/'xbmc/interfaces/builtins/SystemBuiltins.cpp').read_text()
subprocess.run(['git','-C',str(source),'apply','--reverse',str(base/'native/kodi-22.0rc1-dexhub.patch')],check=True)
assert subprocess.run(['git','-C',str(source),'diff'],capture_output=True,check=True).stdout==before_diff
print('PASS: RC1 patch apply/idempotency/reverse; setup before addon scan/services; routing; Back; Now Playing')
