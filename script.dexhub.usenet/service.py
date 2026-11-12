# -*- coding: utf-8 -*-
# SPDX-License-Identifier: GPL-3.0-only
"""Usenet engine (for Dex Hub): the engine inside the app (1.1.0).

Where an app may not start a second program (Apple TV), the engine cannot be the program in
bin/. There it is a library that comes inside the app (Frameworks/NuvioUsenet.framework, built
from the same NuvioTV source plus source/nuvio-usenet-lib/main.go), and this service is its
owner: it loads the library and starts or stops the engine when asked.

Asked how: through properties of Kodi's Home window, so that any add-on can ask without
loading anything of this one.
  dexhub.usenet.inapp       '1' while this service is up and has a library
  dexhub.usenet.app.start   set by the asker to the control token (32+ characters)
  dexhub.usenet.app.port    set here to the engine's port once it listens (127.0.0.1 only)
  dexhub.usenet.app.state   'ready', or 'failed: why'
  dexhub.usenet.app.stop    set by the asker to stop the engine
The library is not loaded before the first start is asked for.
"""
import ctypes
import json
import os
import platform
import sys

import xbmc
import xbmcaddon
import xbmcgui
import xbmcvfs

INAPP, START, STOP, PORT, STATE = ('dexhub.usenet.inapp', 'dexhub.usenet.app.start', 'dexhub.usenet.app.stop',
                                   'dexhub.usenet.app.port', 'dexhub.usenet.app.state')
_lib = None


def log(text, level=xbmc.LOGINFO):
    xbmc.log('[Usenet engine] %s' % text, level)


def library_path():
    """The engine library on this system, '' when there is none."""
    # inside the app (Apple TV): <app>/Frameworks/NuvioUsenet.framework/NuvioUsenet
    folder = xbmcvfs.translatePath('special://xbmc/').rstrip('/')
    for _step in range(5):
        candidate = os.path.join(folder, 'Frameworks', 'NuvioUsenet.framework', 'NuvioUsenet')
        if os.path.isfile(candidate):
            return candidate
        folder = os.path.dirname(folder)
    # beside this add-on (lib/), for a system that lets a library be loaded from there
    system = 'darwin' if sys.platform == 'darwin' else 'linux'
    machine = platform.machine().lower()
    arch = 'arm64' if machine in ('arm64', 'aarch64') else 'amd64' if machine in ('x86_64', 'amd64') else machine
    candidate = os.path.join(xbmcaddon.Addon().getAddonInfo('path'), 'lib',
                             'libnuviousenet-%s-%s.%s' % (system, arch, 'dylib' if system == 'darwin' else 'so'))
    return candidate if os.path.isfile(candidate) else ''


def start(path, token):
    """Load the library (once) and start the engine; returns its port."""
    global _lib
    if _lib is None:
        lib = ctypes.CDLL(path)
        lib.NuvioUsenetStart.argtypes = [ctypes.c_char_p]
        lib.NuvioUsenetStart.restype = ctypes.c_int
        lib.NuvioUsenetPort.restype = ctypes.c_int
        lib.NuvioUsenetStop.restype = None
        _lib = lib
        log('library loaded')
    roots = []
    try:
        with open(xbmcvfs.translatePath('special://xbmc/system/certs/cacert.pem'), 'r', encoding='utf-8',
                  errors='replace') as handle:
            roots = [handle.read()]
    except Exception:
        pass
    cache = xbmcvfs.translatePath('special://temp/usenet-nzb-cache/')
    try:
        os.makedirs(cache, exist_ok=True)
    except OSError:
        cache = ''
    port = _lib.NuvioUsenetStart(json.dumps({'token': token, 'certificates': roots, 'memoryMiB': 128,
                                             'nzbCacheDir': cache}).encode('utf-8'))
    if port <= 0:
        raise RuntimeError('the engine answered %d' % port)
    return port


def stop():
    if _lib is not None:
        try:
            _lib.NuvioUsenetStop()
        except Exception as exc:
            log('stop: %s' % exc, xbmc.LOGWARNING)


def main():
    monitor, home = xbmc.Monitor(), xbmcgui.Window(10000)
    for key in (INAPP, START, STOP, PORT, STATE):
        home.clearProperty(key)
    path = library_path()
    if not path:
        return                      # this system uses the program in bin/, or has no engine
    home.setProperty(INAPP, '1')
    log('ready to start the engine from %s' % path[-60:])
    while not monitor.abortRequested():
        token = home.getProperty(START)
        if token:
            home.clearProperty(START)
            home.clearProperty(PORT)
            try:
                if len(token) < 32:
                    raise ValueError('the token is too short')
                port = start(path, token)
                home.setProperty(STATE, 'ready')
                home.setProperty(PORT, str(port))
                log('engine listening on 127.0.0.1:%d' % port)
            except Exception as exc:
                home.setProperty(STATE, 'failed: %s' % str(exc)[:200])
                log('did not start: %s' % exc, xbmc.LOGERROR)
        if home.getProperty(STOP):
            home.clearProperty(STOP)
            stop()
            home.clearProperty(PORT)
            log('engine stopped')
        if monitor.waitForAbort(0.1):
            break
    stop()
    for key in (INAPP, START, STOP, PORT, STATE):
        home.clearProperty(key)


if __name__ == '__main__':
    main()
