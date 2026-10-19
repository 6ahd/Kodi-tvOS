import importlib.util
import json
import plistlib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from zipfile import ZipFile

base=Path(__file__).resolve().parents[1]
kodi=Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory() as directory:
    app=Path(directory)/'Kodi.app';app.mkdir()
    metadata={'CFBundleIdentifier':'org.xbmc.kodi-tvos','CFBundleDisplayName':'Kodi',
              'CFBundleIcons':{'CFBundlePrimaryIcon':{'CFBundleIconName':'AppIcon'}},
              'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False}}
    (app/'Info.plist').write_bytes(plistlib.dumps(metadata))
    (app/'Assets.car').write_bytes(b'Original Kodi icon fixture')
    for identifier in ['xbmc.core','xbmc.python','xbmc.gui','script.module.pil']:
        shutil.copytree(kodi/'addons'/identifier,app/'AppData/AppHome/addons'/identifier)
    library=app/'lib/python3.11/urllib';library.mkdir(parents=True)
    (library/'request.py').write_text('# Embedded Python fixture\n')
    subprocess.run([sys.executable,str(base/'package_assets.py'),str(base),str(app),'26.0'],check=True)
    result=plistlib.loads((app/'Info.plist').read_bytes())
    for key in ('CFBundleIdentifier','CFBundleDisplayName','CFBundleIcons'):assert result[key]==metadata[key]
    assert (app/'Assets.car').read_bytes()==b'Original Kodi icon fixture'
    manifest=json.loads((app/'AppData/DexHubBundle.json').read_text())
    managed={row['id']:row['version'] for row in manifest['addons']}
    assert managed['plugin.video.dexhub.tvos']=='5.10.342'
    assert managed['skin.dexhub.tvos']=='3.28.79'
    assert managed['script.dexhub.tvos.players']=='1.0.15'
    assert managed['repository.dexworld.appletv']=='1.0.2'
    assert 'repository.dexhub' not in managed
    assert manifest['revision']==21
    assert (app/'AppData/AppHome/addons/plugin.video.dexhub.tvos/resources/lib/phone_files.py').is_file()
    from xml.etree import ElementTree as ET
    skin_files=ET.parse(app/'AppData/AppHome/addons/skin.dexhub.tvos/xml/FileManager.xml')
    phone_button=skin_files.find('.//control[@id="601"]')
    assert phone_button is not None and 'phone_setup' in phone_button.findtext('onclick')
    repository=ET.parse(app/'AppData/AppHome/addons/repository.dexworld.appletv/addon.xml')
    assert repository.findtext('./extension/dir/info')=='https://dexworld.cc/appletv/addons.xml'
    assert managed['script.module.jurialmunkey']=='0.2.35'
    assert managed['script.module.infotagger']=='0.0.9'
    assert managed['script.dexworld.fonts']=='1.0.0'
    assert len(list((app/'AppData/DexHubFonts').glob('*.ttf')))==3
    spec=importlib.util.spec_from_file_location('check_dependencies',base/'check_dependencies.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    module.validate(app/'AppData/AppHome/addons')
    shutil.rmtree(app/'AppData/AppHome/addons/script.module.infotagger')
    try:module.validate(app/'AppData/AppHome/addons')
    except RuntimeError as error:assert 'infotagger' in str(error)
    else:raise AssertionError('A missing required module passed packaging')
    assert not (app/'userdata').exists()
print('PASS: actual packager; dependency closure and missing-module rejection; matching versions; fonts; Kodi name/icon retained')
