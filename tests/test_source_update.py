import hashlib
import json
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

base=Path(__file__).resolve().parents[1]
source=Path(sys.argv[1]).resolve()
before_diff=subprocess.run(['git','-C',str(source),'diff'],capture_output=True,check=True).stdout
def run(*args):
    return subprocess.run([sys.executable,str(base/'apply_bridge.py'),str(source),*args],check=True,capture_output=True,text=True).stdout
run()
assert 'Source files to change: 0' in run('--check')
run()
assert 'Source files to change: 0' in run('--check')
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
native=(base/'native/TVOSAetherPlayer.mm').read_text()
assert native.count('Class bridge = Bridge(')==3
assert '[Bridge(engineName, false) command:request]' in native
assert 'DexKSBridge' not in native and 'DexMPVBridge' not in native
engine=ET.parse(source/'system/settings/darwin_tvos.xml').find('.//setting[@id="videoplayer.dexhubengine"]')
assert engine.findtext('level') == '0' and engine.findtext('default') == '1'
assert [x.text for x in engine.findall('./constraints/options/option')] == ['0','1','2']
assert ET.parse(source/'system/settings/darwin_tvos.xml').find('.//setting[@id="videoplayer.dexhubtruehdatmos"]') is not None
setter=native.split('void CTVOSAetherPlayer::SetSubtitleVerticalPosition',1)[1].split('void CTVOSAetherPlayer::GetAudioCapabilities',1)[0]
assert 'm_lock' not in setter
for backup in sorted((source/'.dexhub-backups').iterdir(),reverse=True):
    manifest=json.loads((backup/'manifest.json').read_text())
    if all((source/entry['path']).is_file() and hashlib.sha256((source/entry['path']).read_bytes()).hexdigest()==entry['after'] for entry in manifest['files']):
        run('--restore',str(backup))
assert not (source/'xbmc/platform/darwin/tvos/TVOSDexHubSetup.mm').exists()
assert subprocess.run(['git','-C',str(source),'diff'],capture_output=True,check=True).stdout==before_diff
assert 'Source files to change: 30' in run('--check')  # v21.43: +6 Apple TV files
print('PASS: RC1 apply/idempotency/restore; setup before addon scan/services; routing; subtitle deadlock fix retained')
