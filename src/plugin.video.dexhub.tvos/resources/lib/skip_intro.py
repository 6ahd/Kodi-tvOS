# -*- coding: utf-8 -*-
"""v5.10.343: «Skip Intro» and «Skip Recap», as in Apple's TV app and Netflix.

When the opening or the recap of a video plays full screen, a button shows in
the corner for as long as it lasts. OK jumps to its end; Back or any other
key leaves the video alone. Nothing skips by itself.

Where the times come from, first found wins:
  1. TheIntroDB (the same service the end-of-episode panel asks), by the
     TMDb id, season and episode Dex Hub plays
  2. the video's own chapters named for them (Intro, Opening, Recap...),
     which Aether gives Kodi from Kodi tvOS v21.43 on

With the TheIntroDB add-on (plugin.video.tidb) installed and enabled, its own
skip buttons are used and this stays off: never two buttons on one opening.
Settings, tvOS, Apple TV: «Skip Intro button» turns it off.
"""
import threading
import time

INTRO_WORDS = ('intro', 'opening', 'vorspann', 'générique de début', 'generique de debut',
               'المقدمة', 'مقدمة', 'تتر البداية', 'شارة البداية')
RECAP_WORDS = ('recap', 'previously', 'résumé', 'resume', 'ملخص', 'سابقا', 'سابقًا')
BUTTON = 100
SHOW_FOR = 12.0          # seconds the button stays up unless the part ends first
END_MARGIN = 3.0         # no button in a part's last seconds
FIRST_PART = 0.5         # openings and recaps sit in the first half


def kind_of(name):
    """'intro', 'recap' or '' for a chapter name."""
    text = ' %s ' % str(name or '').strip().lower()
    if any(word in text for word in RECAP_WORDS):
        return 'recap'
    if any(word in text for word in INTRO_WORDS) or ' op ' in text:
        return 'intro'
    return ''


def api_parts(data, total):
    """[(start, end, kind)] from a TheIntroDB /v3/media answer (milliseconds)."""
    parts = []
    for kind in ('intro', 'recap'):
        for seg in (data or {}).get(kind) or []:
            try:
                start = float(seg.get('start_ms') or 0) / 1000.0
                end = float(seg.get('end_ms')) / 1000.0
            except (AttributeError, TypeError, ValueError):
                continue
            if end - start < 5 or start < 0:
                continue
            if total > 0 and (end > total * FIRST_PART + 120 or end >= total):
                continue
            parts.append((start, end, kind))
    return sorted(parts)


def chapter_bounds(ranges_csv, total):
    """Chapter starts in seconds from Player.Chapters ('b,e,b,e' percentages)."""
    bounds = set()
    for value in str(ranges_csv or '').split(','):
        try:
            percent = float(value)
        except ValueError:
            continue
        if 0 < percent < 100 and total > 0:
            bounds.add(round(percent * total / 100.0, 2))
    return sorted(bounds)


def chapter_part(name, now, bounds, total):
    """(start, end, kind) of the chapter playing now when it is an opening or
    a recap in the first half, else None."""
    kind = kind_of(name)
    if not kind or total <= 0 or now > total * FIRST_PART:
        return None
    start = max([b for b in bounds if b <= now + 0.5] or [0.0])
    later = [b for b in bounds if b > now + 0.5]
    if not later:
        return None
    return (start, later[0], kind)


def active(parts, now):
    for start, end, kind in parts:
        if start - 0.5 <= now < end - END_MARGIN:
            return (start, end, kind)
    return None


# ------------------------------------------------------------------ Kodi side
def _log(msg):
    try:
        import xbmc
        xbmc.log('[DexHub][SkipIntro] %s' % msg, xbmc.LOGINFO)
    except Exception:
        pass


def _info(label):
    import xbmc
    try:
        return xbmc.getInfoLabel(label) or ''
    except Exception:
        return ''


def _cond(expr):
    import xbmc
    try:
        return xbmc.getCondVisibility(expr)
    except Exception:
        return False


def _enabled():
    try:
        import xbmcaddon
        on = (xbmcaddon.Addon('plugin.video.dexhub.tvos').getSetting('appletv_skip_intro') or 'true')
        if on.lower() == 'false':
            return False
    except Exception:
        pass
    try:
        from . import introdb_bridge
        return not introdb_bridge.is_available()
    except Exception:
        return True


def _fetch_parts(total):
    """TheIntroDB parts for what plays, [] when unknown (asked once a video)."""
    try:
        from . import credits_panel
        playing = credits_panel._playing() or {}
    except Exception:
        return []
    q = playing.get('q') or {}
    tmdb, imdb = str(q.get('tmdb') or ''), str(q.get('imdb') or '')
    series = bool(playing.get('series'))
    season, episode = int(playing.get('season') or -1), int(playing.get('episode') or 0)
    if series and (season < 0 or episode <= 0):
        return []
    try:
        from . import tmdb_direct as T
        if not tmdb.isdigit() and imdb:
            tmdb = str((T._season_show('', imdb, cached_only=False) if series
                        else T._resolve_tmdb_id(imdb_id=imdb, media_type='movie')) or '')
        if not tmdb.isdigit():
            return []
        key = 'tidb_intro:%s:%s:%s:%d' % (tmdb, season, episode, int(total))
        hit = T._cache_get(key)
        if hit is not None:
            return [tuple(part) for part in hit]
    except Exception:
        return []
    import json
    from urllib.parse import urlencode
    from urllib.request import Request, urlopen
    params = [('tmdb_id', tmdb)]
    if series:
        params += [('season', season), ('episode', episode)]
    params.append(('duration_ms', int(total * 1000)))
    parts = []
    try:
        req = Request('https://api.theintrodb.org/v3/media?' + urlencode(params),
                      headers={'Accept': 'application/json', 'User-Agent': 'plugin.video.dexhub.tvos'})
        with urlopen(req, timeout=5) as resp:
            parts = api_parts(json.loads(resp.read().decode('utf-8') or '{}'), total)
    except Exception as exc:
        _log('TheIntroDB: %s' % type(exc).__name__)
    try:
        T._cache_set(key, [list(part) for part in parts], 7 * 86400 if parts else 6 * 3600)
    except Exception:
        pass
    return parts


def _skip_window():
    import xbmcgui

    class SkipButton(xbmcgui.WindowXMLDialog):
        def __init__(self, *args, **kwargs):
            super(SkipButton, self).__init__(*args, **kwargs)
            self.label = kwargs.get('label') or ''
            self.result = ''
            self.closed = False
            self.shown = False

        def onInit(self):
            self.shown = True
            self.setProperty('dexhub.skip.label', self.label)
            try:
                self.setFocusId(BUTTON)
            except Exception:
                pass

        def onClick(self, control_id):
            if control_id == BUTTON:
                self.result = 'skip'
                self._done()

        def onAction(self, action):
            # OK reaches onClick; anything else gives the video its keys back.
            if action.getId() in (xbmcgui.ACTION_SELECT_ITEM, 100, 101):
                return
            self.result = 'dismiss'
            self._done()

        def _done(self):
            self.closed = True
            self.close()

    return SkipButton


def _offer(part, monitor, player):
    import xbmc
    import xbmcaddon
    from .i18n import tr
    start, end, kind = part
    label = tr('تخطي الملخص') if kind == 'recap' else tr('تخطي المقدمة')
    path = xbmcaddon.Addon('plugin.video.dexhub.tvos').getAddonInfo('path')
    window = _skip_window()('dexhub_skipintro.xml', path, 'Default', '1080i', label=label)
    window.show()
    shown_at = time.time()
    while not window.closed and not monitor.abortRequested():
        try:
            now = player.getTime()
        except Exception:
            break
        if now >= end - END_MARGIN or now < start - 2 or time.time() - shown_at > SHOW_FOR:
            break
        if not window.shown and time.time() - shown_at > 2.0:
            break  # Kodi refused the dialog (another modal one is up)
        if monitor.waitForAbort(0.25):
            break
    if not window.closed:
        try:
            window.close()
        except Exception:
            pass
    result = window.result
    del window
    if result == 'skip':
        _log('%s skipped to %.1fs' % (kind, end))
        player.seekTime(end)
    return result or 'timeout'


def watch(monitor):
    import xbmc
    player = xbmc.Player()
    video_key, parts, handled = None, [], set()
    lock = threading.Lock()

    def fetch(key, total):
        found = _fetch_parts(total)
        with lock:
            if key == video_key:
                parts[:] = found

    while not monitor.abortRequested():
        wait = 2.0
        try:
            playing = player.isPlayingVideo()
        except Exception:
            playing = False
        if playing and _cond('Window.IsActive(fullscreenvideo)') and _enabled():
            wait = 1.0
            try:
                total, now = player.getTotalTime(), player.getTime()
            except Exception:
                total, now = 0.0, 0.0
            key = '%s|%d' % (_info('Player.Filenameandpath'), int(total))
            if key != video_key and total > 0:
                with lock:
                    video_key, parts[:], handled = key, [], set()
                threading.Thread(target=fetch, args=(key, total), name='DexHub-SkipIntro-fetch',
                                 daemon=True).start()
            with lock:
                part = active(parts, now)
            if part is None:
                part = chapter_part(_info('Player.ChapterName'), now,
                                    chapter_bounds(_info('Player.Chapters'), total), total)
            busy = (_cond('Window.IsVisible(videoosd)') or _cond('Window.IsVisible(seekbar)')
                    or _cond('System.HasActiveModalDialog') or _cond('Player.Paused'))
            if part and not busy and (part[0], part[2]) not in handled:
                handled.add((part[0], part[2]))
                _offer(part, monitor, player)
        if monitor.waitForAbort(wait):
            break
