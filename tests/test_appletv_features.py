"""v21.43 Apple TV features: Top Shelf feed, Skip Intro, PiP button, texture packing,
and (with a Kodi checkout as argument) the source changes and their idempotency."""
import hashlib
import importlib.util
import json
import os
import plistlib
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path
from types import SimpleNamespace

base = Path(__file__).resolve().parents[1]
lib = base / 'src/plugin.video.dexhub.tvos/resources/lib'


def load(name):
    spec = importlib.util.spec_from_file_location(name, lib / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# ---------------------------------------------------------------- Top Shelf feed
shelf = load('appletv_system')
assert shelf.unwrap_image('image://https%3a%2f%2fimage.tmdb.org%2ft%2fp%2fw780%2fa.jpg/') == \
    'https://image.tmdb.org/t/p/w780/a.jpg'
entries = [
    {'file': 'plugin://plugin.video.dexhub.tvos/?action=cw_resume&canonical_id=tt1', 'filetype': 'file',
     'title': 'Pilot', 'showtitle': 'Show', 'season': 1, 'episode': 2,
     'art': {'fanart': 'image://https%3a%2f%2fimg.test%2ff.jpg/', 'poster': 'image://https%3a%2f%2fimg.test%2fp.jpg/'},
     'resume': {'position': 600, 'total': 2400}},
    {'file': 'plugin://plugin.video.dexhub.tvos/?action=streams&canonical_id=tt2', 'filetype': 'directory',
     'title': 'Film', 'season': -1, 'episode': -1, 'art': {'poster': 'http://192.168.1.2/p.jpg|X-Token=a%20b'},
     'resume': {'position': 0, 'total': 0}},
    {'file': 'videodb://movies/1', 'filetype': 'file', 'title': 'Not Dex Hub'},
    {'file': 'plugin://plugin.video.dexhub.tvos/?x', 'filetype': 'file', 'title': ''},
]
asked = []
feed = shelf.feed_from_entries(entries, 'Continue Watching', lambda a: asked.append(a) or '/tmp/%d.jpg' % len(asked))
items = feed['sections'][0]['items']
assert feed['sections'][0]['title'] == 'Continue Watching' and len(items) == 2
assert items[0] == {'title': 'Show · S1E2', 'path': entries[0]['file'], 'shape': 'hdtv', 'folder': False,
                    'progress': 0.25, 'image': '/tmp/1.jpg', 'image_url': 'https://img.test/f.jpg'}
assert items[1]['folder'] is True and items[1]['shape'] == 'poster' and 'progress' not in items[1]
assert 'image_url' not in items[1] and asked[1] == 'http://192.168.1.2/p.jpg|X-Token=a%20b'
assert shelf.feed_from_entries([], 'x') == {'sections': []}
many = [dict(entries[0], file=entries[0]['file'] + str(i)) for i in range(30)]
assert len(shelf.feed_from_entries(many, 'x')['sections'][0]['items']) == shelf.MAX_ITEMS
assert shelf.progress({'resume': {'position': 5000, 'total': 100}}) == 0.99

# pictures: headers after '|' reach the request, only images are kept
with tempfile.TemporaryDirectory() as folder:
    import urllib.request
    seen = {}

    class Answer:
        def __init__(self, kind):
            self.headers = {'Content-Type': kind}
        def __enter__(self):
            return self
        def __exit__(self, *args):
            return False
        def read(self, size):
            return b'\x89PNG...'
    real = urllib.request.urlopen
    try:
        urllib.request.urlopen = lambda req, timeout: (seen.update(req.headers) or Answer(seen.get('Kind', 'image/png')))
        keep = set()
        local = shelf._download('http://192.168.1.2/p.png|X-Token=a%20b', folder, keep)
        assert local.endswith('.png') and Path(local).read_bytes() == b'\x89PNG...' and len(keep) == 1
        assert seen['X-token'] == 'a b'
        assert shelf._download('http://192.168.1.2/p.png', folder, set()) == local  # cached
        urllib.request.urlopen = lambda req, timeout: Answer('text/html')
        assert shelf._download('https://x.test/page', folder, set()) == ''
        assert shelf._download('javascript:alert(1)', folder, set()) == ''
    finally:
        urllib.request.urlopen = real

# ---------------------------------------------------------------- Skip Intro
skip = load('skip_intro')
assert skip.kind_of('Opening Credits') == 'intro' and skip.kind_of('OP') == 'intro'
assert skip.kind_of('Previously on') == 'recap' and skip.kind_of('Chapter 3') == ''
assert skip.kind_of('المقدمة') == 'intro' and skip.kind_of('Operation') == ''
data = {'intro': [{'start_ms': 30000, 'end_ms': 95000}, {'start_ms': 10, 'end_ms': None}],
        'recap': [{'start_ms': 0, 'end_ms': 28000}], 'credits': [{'start_ms': 2500000, 'end_ms': 2600000}]}
parts = skip.api_parts(data, 2700)
assert parts == [(0.0, 28.0, 'recap'), (30.0, 95.0, 'intro')]
assert skip.active(parts, 40) == (30.0, 95.0, 'intro')
assert skip.active(parts, 93) is None   # last seconds: no button
assert skip.active(parts, 100) is None
# Player.Chapters: start,end percentage pairs of 0-60s, 60-150s, 150s-...
bounds = skip.chapter_bounds('0.00000,2.00000,2.00000,5.00000,5.00000,100.00000', 3000)
assert bounds == [60.0, 150.0]
assert skip.chapter_part('Intro', 70, bounds, 3000) == (60.0, 150.0, 'intro')
assert skip.chapter_part('Intro', 2000, bounds, 3000) is None   # second half
assert skip.chapter_part('Chapter 2', 70, bounds, 3000) is None
assert skip.chapter_part('Intro', 200, bounds, 3000) is None    # last chapter: no end

# ---------------------------------------------------------------- PiP button
sys.modules.setdefault('xbmc', SimpleNamespace(getCondVisibility=lambda _: True))
sys.modules.setdefault('xbmcgui', SimpleNamespace(WindowXMLDialog=object, WindowXML=object))
osd = load('osd_buttons')
old = 'sources,episodes,info,audio,subtitles,subsync,-nextsub,external,video,ppi'
assert [k for k, _ in osd._parse(old)] == list(osd.KEYS)
assert dict(osd._parse(old))['pip'] is True
assert [k for k, on in osd._parse(old) if on].index('pip') == [k for k, on in osd._parse(old) if on].index('external') + 1
assert len([k for k, on in osd._parse('') if on]) <= osd.SLOTS
for table in (osd.NAMES, osd.NOTES, osd.DOES, osd.ICONS):
    assert 'pip' in table
assert (lib.parent / 'media/osdbar/pip.png').is_file()
skin = base / 'src/skin.dexhub.tvos'
player = (skin / 'xml/Includes_DexPlayer.xml').read_text()
ET.fromstring(player)
assert len(re.findall(r'_pip\b', player)) == len(re.findall(r'_ppi\b', player))
for n in range(1, 11):
    assert 'name="DhOsdIs_%d_pip"' % n in player
    assert '$EXP[DhOsdIs_%d_pip]">DexHub.PictureInPicture</onclick>' % n in player
    vis = re.search(r'<expression name="DhOsdSlotVis_%d">(.*)</expression>' % n, player).group(1)
    assert '[$EXP[DhOsdIs_%d_pip] + $EXP[DhOsdOk_pip]]' % n in vis and vis.count('[') == vis.count(']')
assert 'String.IsEqual(Player.Process(videodecoder),Aether)' in player
assert (skin / 'media/dexhub/osd/pip.png').is_file()
for lang in ('en_gb', 'ar_sa'):
    assert 'msgctxt "#32151"' in (skin / ('language/resource.language.%s/strings.po' % lang)).read_text()
ET.parse(lib.parent / 'skins/Default/1080i/dexhub_skipintro.xml')
settings = ET.parse(lib.parent.parent / 'resources/settings.xml')
ids = {s.get('id') for s in settings.iter('setting')}
assert {'appletv_topshelf', 'appletv_skip_intro'} <= ids
actions = [s.get('action') for s in settings.iter('setting') if s.get('action')]
assert 'DexHub.AppleTVUser(link)' in actions and 'DexHub.AppleTVUser(unlink)' in actions

# ---------------------------------------------------------------- texture bundle
with tempfile.TemporaryDirectory() as directory:
    app = Path(directory) / 'Kodi.app'
    media = app / 'AppData/AppHome/addons/skin.dexhub.tvos/media'
    (media / 'dexhub/osd').mkdir(parents=True)
    (media / 'a.png').write_bytes(b'png')
    (media / 'dexhub/osd/b.jpg').write_bytes(b'jpg')
    (media / 'notes.txt').write_text('x')
    log = Path(directory) / 'packer.log'
    packer = Path(directory) / 'TexturePacker'
    packer.write_text('#!/bin/sh\n'
                      'echo "$@" > %s\n'
                      'find "$2" -type f | sed "s|$2/||" | sort >> %s\n'
                      'echo bundle > "$4"\n' % (log, log))
    packer.chmod(0o755)
    out = subprocess.run(['bash', str(base / 'pack_textures.sh'), str(app), str(packer)],
                         check=True, capture_output=True, text=True).stdout
    assert 'packed: 2 images' in out and (media / 'Textures.xbt').read_text() == 'bundle\n'
    lines = log.read_text().split('\n')
    assert lines[0].endswith('-dupecheck') and lines[1:3] == ['a.png', 'dexhub/osd/b.jpg']
    assert (media / 'a.png').is_file()     # loose files stay for full-path references
    out = subprocess.run(['bash', str(base / 'pack_textures.sh'), str(app), ''],
                         check=True, capture_output=True, text=True).stdout
    assert 'stay loose' in out

# ---------------------------------------------------------------- bridge contract
bridge = (base / 'DexAetherEmbedded.swift').read_text()
for selector in ('@objc(togglePictureInPicture)', '@objc(pictureInPictureState)'):
    assert selector in bridge
assert 'engine.pictureInPictureActive = active' in bridge and '"chapters": chapterRows' in bridge
assert 'AVPictureInPictureController(playerLayer: layer)' in bridge
native = (base / 'native/TVOSAetherPlayer.mm').read_text()
assert 'SetChapters(marks)' in native and 'int CTVOSAetherPlayer::SeekChapter' in native
assert 'dispatch_sync' not in native
scene = (base / 'native/scene-lifecycle.txt').read_text()
assert 'DexHubPictureInPictureActive()' in scene and 'DexAetherPictureInPictureDidStop' in scene
release = json.loads((base / 'ENGINE-RELEASE.json').read_text())
assert release['bridge_revision'] == 22 and release['app_version'] == '21.43'
assert 'togglePictureInPicture pictureInPictureState' in (base / 'build.sh').read_text()

# ---------------------------------------------------------------- Kodi source
if len(sys.argv) > 1:
    source = Path(sys.argv[1]).resolve()

    def run(*args):
        return subprocess.run([sys.executable, str(base / 'apply_bridge.py'), str(source), *args],
                              check=True, capture_output=True, text=True).stdout
    before = set((source / '.dexhub-backups').glob('*')) if (source / '.dexhub-backups').exists() else set()
    run()
    assert 'Source files to change: 0' in run('--check')
    tvos = source / 'xbmc/platform/darwin/tvos'
    builtins = (source / 'xbmc/interfaces/builtins/SystemBuiltins.cpp').read_text()
    for name in ('dexhub.pictureinpicture', 'dexhub.topshelf', 'dexhub.appletvuser'):
        assert builtins.count('"%s"' % name) == 1
    assert builtins.index('#if defined(TARGET_DARWIN_TVOS)\n          {"dexhub.') > 0
    shelf_info = plistlib.loads((tvos / 'TopShelf/Info.plist.in').read_bytes())['NSExtension']
    assert shelf_info == {'NSExtensionPointIdentifier': 'com.apple.tv-top-shelf',
                          'NSExtensionPrincipalClass': 'ServiceProvider'}
    assert 'TVTopShelfContentProvider' in (tvos / 'TopShelf/ServiceProvider.h').read_text()
    top = (tvos / 'TVOSTopShelf.mm').read_text()
    assert 'DexHubRunTopShelfItem(split[2], split[4])' in top and 'if (split.size() < 5)' in top
    assert 'audio' in plistlib.loads((tvos / 'Info.plist.in').read_bytes())['UIBackgroundModes']
    application = (tvos / 'XBMCApplication.mm').read_text()
    assert scene in application and application.count('@implementation DexHubSceneDelegate') == 1
    cmake = (tvos / 'CMakeLists.txt').read_text()
    assert cmake.count('TVOSDexHubSystem.mm') == 1 and cmake.count('TVOSDexHubSystem.h') == 1
    subprocess.run(['git', '-C', str(source), 'diff', '--check'], check=True)
    # restore everything this run changed, newest backup first
    for backup in sorted(set((source / '.dexhub-backups').glob('*')) - before, reverse=True):
        run('--restore', str(backup))
print('PASS: Top Shelf feed and pictures, Skip Intro parts, PiP button in every slot, texture bundle, '
      'bridge contract' + (', Kodi source apply/idempotency/restore' if len(sys.argv) > 1 else ''))
