# -*- coding: utf-8 -*-
"""v5.10.343: Apple TV system features (Kodi tvOS v21.43).

Top Shelf
    Continue Watching above the app icon on the Apple TV Home screen, with
    the progress of each title, as in Apple's TV app. The rows are read from
    Dex Hub's own Continue Watching listing (the same paths its cards open),
    their pictures are kept in the add-on's folder, and the app's
    ``DexHub.TopShelf`` builtin hands them to the Top Shelf extension.
    Published shortly after start, after a video stops, and every half hour.

Apple TV users
    ``DexHub.AppleTVUser(sync)`` at start opens the Kodi profile linked to the
    Apple TV user who is watching (Settings, tvOS, Apple TV). Without the
    user-management entitlement in the app's signature Apple TV does not say
    who is watching, and nothing changes.

The service runs ``run(monitor)``; ``feed_from_entries`` is pure for tests.
"""
import hashlib
import json
import os
import time
from urllib.parse import unquote

LISTING = 'plugin://plugin.video.dexhub.tvos/?action=widget_continue'
PROPERTIES = ['title', 'art', 'resume', 'showtitle', 'season', 'episode']
MAX_ITEMS = 10
MAX_IMAGE_BYTES = 4 * 1024 * 1024
FIRST_DELAY = 45
REFRESH_EVERY = 30 * 60
AFTER_PLAYBACK = 20
WIDE_ART = ('landscape', 'episode.landscape', 'fanart', 'tvshow.fanart', 'thumb')
POSTER_ART = ('poster', 'tvshow.poster', 'thumb')


def _log(msg, level=None):
    try:
        import xbmc
        xbmc.log('[DexHub][AppleTV] %s' % msg, xbmc.LOGINFO if level is None else level)
    except Exception:
        pass


def unwrap_image(url):
    """Kodi's image://<quoted url>/ form back to the address it wraps."""
    url = str(url or '').strip()
    if url.startswith('image://'):
        url = unquote(url[len('image://'):])
        if url.endswith('/'):
            url = url[:-1]
    return url


def pick_image(art):
    """(address, shape): a wide picture first (Apple's TV app uses 16:9
    cards), else the poster."""
    art = art or {}
    for key in WIDE_ART:
        value = unwrap_image(art.get(key))
        if value:
            return value, 'hdtv'
    for key in POSTER_ART:
        value = unwrap_image(art.get(key))
        if value:
            return value, 'poster'
    return '', 'hdtv'


def progress(entry):
    resume = (entry or {}).get('resume') or {}
    try:
        position, total = float(resume.get('position') or 0), float(resume.get('total') or 0)
    except (TypeError, ValueError):
        return 0.0
    if position <= 0 or total <= 0:
        return 0.0
    return round(min(0.99, position / total), 3)


def card_title(entry):
    entry = entry or {}
    show = str(entry.get('showtitle') or '').strip()
    try:
        season, episode = int(entry.get('season') or -1), int(entry.get('episode') or -1)
    except (TypeError, ValueError):
        season, episode = -1, -1
    if show and season >= 0 and episode > 0:
        return '%s · S%dE%d' % (show, season, episode)
    return str(entry.get('title') or entry.get('label') or show).strip()


def feed_from_entries(entries, section_title, image_for=None):
    """The DexHub.TopShelf feed from a Files.GetDirectory listing.

    ``image_for(address)`` returns a local copy of a picture or ''. Only
    plugin:// rows go on the shelf (the app plays nothing else from it)."""
    items = []
    for entry in entries or []:
        path = str((entry or {}).get('file') or '')
        if not path.startswith('plugin://'):
            continue
        title = card_title(entry)
        if not title:
            continue
        address, shape = pick_image(entry.get('art'))
        item = {'title': title, 'path': path, 'shape': shape,
                'folder': entry.get('filetype') == 'directory'}
        share = progress(entry)
        if share:
            item['progress'] = share
        if address:
            local = image_for(address) if image_for else ''
            if local:
                item['image'] = local
            if address.startswith('https://'):
                item['image_url'] = address.split('|', 1)[0]
        items.append(item)
        if len(items) >= MAX_ITEMS:
            break
    if not items:
        return {'sections': []}
    return {'sections': [{'title': section_title, 'items': items}]}


# ------------------------------------------------------------------ Kodi side
def _folder():
    import xbmcvfs
    path = xbmcvfs.translatePath('special://profile/addon_data/plugin.video.dexhub.tvos/topshelf')
    os.makedirs(path, exist_ok=True)
    return path


def _enabled(key):
    try:
        import xbmcaddon
        return (xbmcaddon.Addon('plugin.video.dexhub.tvos').getSetting(key) or 'true').lower() != 'false'
    except Exception:
        return True


def _entries():
    import xbmc
    request = {'jsonrpc': '2.0', 'id': 'dexhub-topshelf', 'method': 'Files.GetDirectory',
               'params': {'directory': LISTING, 'media': 'video', 'properties': PROPERTIES}}
    try:
        answer = json.loads(xbmc.executeJSONRPC(json.dumps(request)) or '{}')
    except Exception as exc:
        _log('listing unreadable: %s' % exc)
        return None
    if 'error' in answer:
        _log('listing refused: %s' % answer['error'])
        return None
    return (answer.get('result') or {}).get('files') or []


def _download(address, folder, keep):
    """A local copy of a picture (http, https or a file), or ''."""
    if not address:
        return ''
    if address.startswith('/') or address.startswith('special://'):
        return address
    if not (address.startswith('http://') or address.startswith('https://')):
        return ''
    url, _sep, header_text = address.partition('|')
    name = hashlib.sha256(url.encode('utf-8')).hexdigest()[:24]
    ext = os.path.splitext(url.split('?', 1)[0])[1].lower()
    name += ext if ext in ('.jpg', '.jpeg', '.png', '.webp') else '.jpg'
    target = os.path.join(folder, name)
    keep.add(name)
    if os.path.isfile(target) and os.path.getsize(target) > 0:
        return target
    headers = {'User-Agent': 'plugin.video.dexhub.tvos'}
    for pair in header_text.split('&') if header_text else []:
        key, _eq, value = pair.partition('=')
        if key and value:
            headers[unquote(key)] = unquote(value)
    try:
        from urllib.request import Request, urlopen
        with urlopen(Request(url, headers=headers), timeout=8) as resp:
            if not str(resp.headers.get('Content-Type') or 'image/').startswith('image/'):
                return ''
            data = resp.read(MAX_IMAGE_BYTES + 1)
        if not data or len(data) > MAX_IMAGE_BYTES:
            return ''
        partial = target + '.part'
        with open(partial, 'wb') as handle:
            handle.write(data)
        os.replace(partial, target)
        return target
    except Exception as exc:
        _log('picture skipped: %s' % type(exc).__name__)
        keep.discard(name)
        return ''


def _section_title():
    try:
        from .i18n import tr
        return tr('متابعة المشاهدة')
    except Exception:
        return 'متابعة المشاهدة'


def publish():
    """Write the feed and hand it to the app. Returns the number of cards."""
    import xbmc
    folder = _folder()
    feed_path = os.path.join(folder, 'feed.json')
    if _enabled('appletv_topshelf'):
        entries = _entries()
        if entries is None:
            return -1
        keep = set()
        feed = feed_from_entries(entries, _section_title(),
                                 lambda address: _download(address, folder, keep))
        for name in os.listdir(folder):
            if name not in keep and name != 'feed.json':
                try:
                    os.remove(os.path.join(folder, name))
                except OSError:
                    pass
    else:
        feed = {'sections': []}
    with open(feed_path + '.part', 'w', encoding='utf-8') as handle:
        json.dump(feed, handle, ensure_ascii=False)
    os.replace(feed_path + '.part', feed_path)
    xbmc.executebuiltin('DexHub.TopShelf("%s")' % feed_path.replace('"', ''))
    count = sum(len(section['items']) for section in feed['sections'])
    _log('Top Shelf: %d cards' % count)
    return count


def run(monitor):
    import xbmc
    # The profile linked to the Apple TV user who is watching, first; then a
    # Top Shelf card that launched the app (it waited for Kodi to be ready).
    xbmc.executebuiltin('DexHub.AppleTVUser(sync)')
    xbmc.executebuiltin('DexHub.TopShelf')
    player = xbmc.Player()
    due = time.time() + FIRST_DELAY
    was_playing = False
    while not monitor.abortRequested():
        try:
            playing = player.isPlayingVideo()
        except Exception:
            playing = False
        if was_playing and not playing:
            due = min(due, time.time() + AFTER_PLAYBACK)
        was_playing = playing
        if not playing and time.time() >= due:
            try:
                publish()
            except Exception as exc:
                _log('Top Shelf not published: %s' % exc, xbmc.LOGWARNING)
            due = time.time() + REFRESH_EVERY
        if monitor.waitForAbort(5):
            break
