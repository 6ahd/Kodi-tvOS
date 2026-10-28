"""Dex Hub's Continue Watching on the Apple TV Top Shelf.

Reads the add-on's own Continue Watching folder through JSON-RPC and hands
the rows to Kodi's TopShelf.Set builtin, which keeps them where the Top Shelf
extension reads them. Play resumes the title; Select on a folder (a source
picker) opens it in Kodi.
"""
import json
import os
from urllib.parse import unquote

import xbmc
import xbmcvfs

SOURCE = 'plugin://plugin.video.dexhub.tvos/?action=continue'
FILE = 'special://temp/dexhub-topshelf.json'
EVERY = 30 * 60
LIMIT = 12


def _image(art):
    for key in ('landscape', 'tvshow.landscape', 'fanart', 'tvshow.fanart', 'thumb', 'poster'):
        value = (art or {}).get(key) or ''
        if value.startswith('image://'):
            value = unquote(value[len('image://'):].rstrip('/'))
        if value.startswith(('http://', 'https://', '/', 'special://')):
            return value
    return ''


def _title(row):
    show = row.get('showtitle') or ''
    season, episode = row.get('season', -1), row.get('episode', -1)
    if show and isinstance(season, int) and isinstance(episode, int) and season >= 0 and episode >= 0:
        return '%s · S%d E%d' % (show, season, episode)
    return row.get('title') or row.get('label') or ''


def _rows():
    request = {'jsonrpc': '2.0', 'id': 1, 'method': 'Files.GetDirectory',
               'params': {'directory': SOURCE, 'media': 'video',
                          'properties': ['title', 'art', 'showtitle', 'season', 'episode', 'resume']}}
    answer = json.loads(xbmc.executeJSONRPC(json.dumps(request)) or '{}')
    items = []
    for row in (answer.get('result') or {}).get('files') or []:
        path = row.get('file') or ''
        if not path:
            continue
        quoted = path.replace('"', '%22')
        folder = row.get('filetype') == 'directory'
        action = 'ActivateWindow(Videos,"%s",return)' % quoted if folder else 'PlayMedia("%s")' % quoted
        item = {'title': _title(row), 'image': _image(row.get('art')), 'play': action, 'display': action}
        resume = row.get('resume') or {}
        if resume.get('total'):
            item['progress'] = round(float(resume.get('position') or 0) / float(resume['total']), 3)
        items.append(item)
        if len(items) >= LIMIT:
            break
    return items


def refresh():
    """Send the current Continue Watching to the Top Shelf (no rows: Dex Hub's picture)."""
    try:
        items = _rows()
    except Exception as error:
        xbmc.log('DexHub Top Shelf: Continue Watching unavailable (%s)' % error, xbmc.LOGWARNING)
        return
    arabic = xbmc.getLanguage(xbmc.ISO_639_1) == 'ar'
    shelf = {'sections': [{'title': 'متابعة المشاهدة' if arabic else 'Continue Watching', 'items': items}] if items else []}
    path = xbmcvfs.translatePath(FILE)
    with open(path, 'w', encoding='utf-8') as handle:
        json.dump(shelf, handle, ensure_ascii=False)
    xbmc.executebuiltin('TopShelf.Set("%s")' % path)
    xbmc.log('DexHub Top Shelf: %d item(s)' % len(items), xbmc.LOGINFO)


class _Watcher(xbmc.Player):
    """Notes when something stops, so the shelf follows what was watched."""
    def __init__(self):
        super().__init__()
        self.stopped = False

    def onPlayBackStopped(self):
        self.stopped = True

    def onPlayBackEnded(self):
        self.stopped = True


def run(monitor):
    """Refresh after start-up settles, after each watch, and every half hour."""
    watcher = _Watcher()
    if monitor.waitForAbort(45):
        return
    waited = EVERY
    while True:
        if (watcher.stopped or waited >= EVERY) and not xbmc.getCondVisibility('Player.HasVideo'):
            watcher.stopped = False
            waited = 0
            if monitor.waitForAbort(8):  # let Dex Hub save the position first
                return
            refresh()
        if monitor.waitForAbort(10):
            return
        waited += 10
