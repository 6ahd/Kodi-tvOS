"""Move the bundled update source to the Apple TV repository once."""
import json
import os
import xml.etree.ElementTree as ET

import xbmc
import xbmcaddon
import xbmcvfs


def migrate():
    marker = 'special://profile/addon_data/script.dexhub.tvos.players/appletv-repository-v1.done'
    if xbmcvfs.exists(marker):
        return False
    xbmcaddon.Addon('repository.dexworld.appletv')

    def enable(identifier, enabled):
        result = json.loads(xbmc.executeJSONRPC(json.dumps({
            'jsonrpc': '2.0', 'id': 1, 'method': 'Addons.SetAddonEnabled',
            'params': {'addonid': identifier, 'enabled': enabled}})))
        if 'error' in result:
            raise RuntimeError('Repository state change failed: ' + identifier)

    enable('repository.dexworld.appletv', True)
    try:
        old = xbmcaddon.Addon('repository.dexhub')
    except RuntimeError:
        old = None
    if old is not None:
        descriptor = os.path.join(old.getAddonInfo('path'), 'addon.xml')
        stream = xbmcvfs.File(descriptor)
        try:
            root = ET.fromstring(stream.read())
        finally:
            stream.close()
        urls = [node.text or '' for node in root.findall('./extension/dir/info')]
        if any(url.rstrip('/') == 'https://dexworld.cc/dexhub/addons.xml' for url in urls):
            enable('repository.dexhub', False)
    xbmcvfs.mkdirs('special://profile/addon_data/script.dexhub.tvos.players/')
    stream = xbmcvfs.File(marker, 'w')
    try:
        stream.write('https://dexworld.cc/appletv/')
    finally:
        stream.close()
    xbmc.log('DexHub: Apple TV update repository configured', xbmc.LOGINFO)
    return True
