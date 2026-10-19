#!/usr/bin/env python3
"""Export separately named Apple TV addons and a repository for a real URL."""
import argparse, hashlib, shutil, xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import urlsplit
from zipfile import ZipFile, ZIP_DEFLATED
p=argparse.ArgumentParser()
p.add_argument('--url',required=True,help='Public base URL where the exported directory will be hosted')
p.add_argument('--output',type=Path,default=Path.home()/'Downloads/DexHub-AppleTV-Repo')
a=p.parse_args();url=a.url.rstrip('/')+'/'
if urlsplit(url).scheme not in ('http','https') or not urlsplit(url).netloc:raise SystemExit('Supply a real HTTP(S) repository base URL')
base=Path(__file__).resolve().parent;out=a.output.resolve();out.mkdir(parents=True,exist_ok=True);index=ET.Element('addons')
for archive in sorted((base/'assets').glob('*.zip')):
 with ZipFile(archive) as z:
  descriptors=[n for n in z.namelist() if n.count('/')==1 and n.endswith('/addon.xml')]
  if len(descriptors)!=1:raise SystemExit('Unexpected addon ZIP: '+archive.name)
  addon=ET.fromstring(z.read(descriptors[0]));addon_id=addon.attrib['id'];version=addon.attrib['version']
  if '/' in addon_id or '..' in addon_id:raise SystemExit('Unexpected addon in Apple TV assets')
  folder=out/addon_id;folder.mkdir(exist_ok=True);destination=folder/f'{addon_id}-{version}.zip';shutil.copyfile(archive,destination)
  destination.with_suffix('.zip.md5').write_text(hashlib.md5(destination.read_bytes()).hexdigest())
  (folder/'addon.xml').write_bytes(ET.tostring(addon,encoding='utf-8',xml_declaration=True))
  for element in addon.findall('./extension/assets/*'):
   if element.text and addon_id+'/'+element.text in z.namelist():
    path=folder/element.text;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(z.read(addon_id+'/'+element.text))
  index.append(addon)
repo_id='repository.dexworld.appletv'
repo=ET.parse(base/repo_id/'addon.xml').getroot()
directory=repo.find('./extension[@point="xbmc.addon.repository"]/dir')
directory.find('info').text=url+'addons.xml'
directory.find('checksum').text=url+'addons.xml.md5'
directory.find('datadir').text=url
folder=out/repo_id;folder.mkdir(exist_ok=True);(folder/'addon.xml').write_bytes(ET.tostring(repo,encoding='utf-8',xml_declaration=True))
archive=folder/(repo_id+'-'+repo.get('version')+'.zip')
with ZipFile(archive,'w',ZIP_DEFLATED) as z:z.write(folder/'addon.xml',repo_id+'/addon.xml')
archive.with_suffix('.zip.md5').write_text(hashlib.md5(archive.read_bytes()).hexdigest());index.append(repo)
content=ET.tostring(index,encoding='utf-8',xml_declaration=True);(out/'addons.xml').write_bytes(content);(out/'addons.xml.md5').write_text(hashlib.md5(content).hexdigest())
print('Ready to host:',out)
print('Install repository ZIP:',archive)
print('Native Aether support still requires the rebuilt Kodi IPA.')
