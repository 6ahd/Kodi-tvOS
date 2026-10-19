"""v20: the trailer watcher's per-tick publishing must not rebuild Addon() each time."""
import importlib
import sys
import tempfile
import types
from pathlib import Path

base = Path(__file__).resolve().parents[1]
lib = base / 'src/plugin.video.dexhub.tvos/resources/lib'
package = types.ModuleType('idle_fixture'); package.__path__ = [str(lib)]
sys.modules['idle_fixture'] = package
made = []
settings = {'homeui_trailers': 'true', 'homeui_trailer_mode': 'background', 'ui_language': 'English'}
with tempfile.TemporaryDirectory() as tmp:
    class Addon(object):
        def __init__(self, *a):
            made.append(1)
        def getSetting(self, key): return settings.get(key, '')
        def setSetting(self, key, value): settings[key] = value
        def getAddonInfo(self, key): return tmp
    props = {}
    class Window(object):
        def __init__(self, *a): pass
        def getProperty(self, k): return props.get(k, '')
        def setProperty(self, k, v): props[k] = v
    sys.modules['xbmcaddon'] = types.SimpleNamespace(Addon=Addon)
    sys.modules['xbmcvfs'] = types.SimpleNamespace(translatePath=lambda p: p)
    sys.modules['xbmcgui'] = types.SimpleNamespace(Window=Window)
    sys.modules['xbmc'] = types.SimpleNamespace(log=lambda *a: None, LOGINFO=1, LOGWARNING=2, LOGDEBUG=0)
    tp = importlib.import_module('idle_fixture.trailer_preferences')
    tp.publish_presentation('background')
    tp.publish_status('waiting')
    initial = len(made)
    for _ in range(200):
        tp.publish_presentation('background')
        tp.publish_status('waiting')
    assert len(made) == initial <= 3, 'Addon() built %d times for 400 publishes' % len(made)
    assert props['dhs.trailer.enabled'] == '1' and props['dhs.trailer.notice'].startswith('Select')
    settings['homeui_trailers'] = 'false'
    tp.invalidate(); tp.publish_presentation()
    assert props['dhs.trailer.enabled'] == '0', 'invalidate() must apply a changed setting at once'
print('PASS: 400 trailer publishes reuse cached settings (%d Addon builds); invalidate applies changes at once' % initial)
