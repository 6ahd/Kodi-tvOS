import xbmc
from dexhub_navigation import install_keymap

if xbmc.getCondVisibility('System.Platform.TVOS'):
    try:
        from repository_setup import migrate
        migrate()
    except Exception:
        xbmc.log('DexHub: Apple TV repository migration remains pending', xbmc.LOGWARNING)
    try:
        from stable_defaults import install as install_defaults
        install_defaults()
    except Exception:
        xbmc.log('DexHub: Aether preference remains pending', xbmc.LOGWARNING)
    try:
        from ui_quality import install
        install()
    except Exception:
        xbmc.log('DexHub: artwork settings were left unchanged',xbmc.LOGWARNING)

if install_keymap():
    monitor = xbmc.Monitor()
    # Kodi can ignore reloads while the startup dialogs close.
    for delay in (1.0, 2.0):
        if monitor.waitForAbort(delay):
            break
        xbmc.executebuiltin('Action(reloadkeymaps)')

if xbmc.getCondVisibility('System.Platform.TVOS'):
    monitor = xbmc.Monitor()
    if not monitor.waitForAbort(10):
        try:
            import importlib.util
            import os
            import xbmcaddon
            path = os.path.join(xbmcaddon.Addon('plugin.video.dexhub.tvos').getAddonInfo('path'),
                                'resources', 'lib', 'full_backup.py')
            spec = importlib.util.spec_from_file_location('dexhub_full_restore', path)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            module.apply_core_restore()
            import xbmcvfs
            profile = xbmcaddon.Addon('plugin.video.dexhub.tvos').getAddonInfo('profile')
            if xbmcvfs.exists(profile.rstrip('/\\') + '/.dexhub-json-restore-pending.json'):
                xbmc.executebuiltin('RunPlugin(plugin://plugin.video.dexhub.tvos/?action=config_json_restore_pending)')
        except Exception:
            xbmc.log('DexHub restore: core settings remain pending', xbmc.LOGWARNING)
        # Avoid repository scans competing with startup/video decoding.
        while not monitor.waitForAbort(30):
            if not xbmc.getCondVisibility('Player.HasVideo'):
                xbmc.executebuiltin('UpdateAddonRepos')
                break
