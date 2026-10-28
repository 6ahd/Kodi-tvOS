"""Raise artwork cache limits while preserving all existing Kodi settings."""
import xml.etree.ElementTree as ET
import xbmc
import xbmcvfs

def install(force=False):
    marker='special://profile/addon_data/script.dexhub.tvos.players/ui-quality-v2.done'
    if not force and xbmcvfs.exists(marker):return False
    path='special://profile/advancedsettings.xml'
    raw=''
    if xbmcvfs.exists(path):
        f=xbmcvfs.File(path)
        try:raw=f.read()
        finally:f.close()
    root=ET.fromstring(raw) if raw.strip() else ET.Element('advancedsettings')
    if root.tag!='advancedsettings':raise ValueError('Invalid advancedsettings.xml; left unchanged')
    for tag,value in [('imageres',1440),('fanartres',2160)]:
        element=root.find(tag)
        if element is None:element=ET.SubElement(root,tag)
        try:current=int(element.text or 0)
        except ValueError:current=0
        element.text=str(max(current,value))
    backup='special://profile/advancedsettings.before-dexhub-quality.xml'
    if raw and not xbmcvfs.exists(backup):
        f=xbmcvfs.File(backup,'w')
        try:f.write(raw)
        finally:f.close()
    f=xbmcvfs.File(path,'w')
    try:f.write(ET.tostring(root,encoding='unicode'))
    finally:f.close()
    xbmcvfs.mkdirs('special://profile/addon_data/script.dexhub.tvos.players/')
    f=xbmcvfs.File(marker,'w')
    try:f.write('1')
    finally:f.close()
    xbmc.log('DexHub: artwork cache minimums set to 1440/2160; applied at next Kodi launch',xbmc.LOGINFO)
    return True
