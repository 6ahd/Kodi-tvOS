# -*- coding: utf-8 -*-
"""Usenet engine (for Dex Hub): this add-on only carries the engine's programs (bin/) and their
licences. Run from Kodi's add-on list it says what it is and whether this device has a program."""
import os
import platform
import sys

import xbmc
import xbmcaddon
import xbmcgui


def program_name():
    if xbmc.getCondVisibility('System.Platform.Android') or xbmc.getCondVisibility('System.Platform.IOS') \
            or xbmc.getCondVisibility('System.Platform.TVOS'):
        return ''
    system = 'darwin' if sys.platform == 'darwin' else 'windows' if sys.platform.startswith('win') else 'linux'
    machine = platform.machine().lower()
    arch = 'arm64' if machine in ('arm64', 'aarch64') else 'amd64' if machine in ('x86_64', 'amd64') else machine
    return 'nuvio-usenet-%s-%s%s' % (system, arch, '.exe' if system == 'windows' else '')


def main():
    addon = xbmcaddon.Addon()
    name = program_name()
    here = os.path.join(addon.getAddonInfo('path'), 'bin', name) if name else ''
    arabic = xbmc.getLanguage(xbmc.ISO_639_1) == 'ar'
    if xbmcgui.Window(10000).getProperty('dexhub.usenet.inapp') == '1' and not (here and os.path.isfile(here)):
        text = (u'محرك Usenet داخل التطبيق نفسه، وهذي الإضافة تشغّله لما يطلبه Dex Hub.\nالمزود والمفهرسات من: Dex Hub ← الإعدادات ← مصادر التشغيل ← Usenet.'
                if arabic else u'The Usenet engine is inside the app itself, and this add-on starts it when Dex Hub asks.\nSet your provider and indexers in Dex Hub, Settings, Stream sources, Usenet.')
    elif here and os.path.isfile(here):
        text = (u'محرك Usenet موجود لهذا الجهاز (%s).\nDex Hub يشغله لحاله. المزود والمفهرسات من: Dex Hub ← الإعدادات ← مصادر التشغيل ← Usenet.'
                if arabic else u'This device has its Usenet engine (%s).\nDex Hub starts it by itself. Set your provider and indexers in Dex Hub, Settings, Stream sources, Usenet.') % name
    else:
        text = (u'ما فيه برنامج لهذا الجهاز (%s).' if arabic else u'There is no program for this device (%s).') % (name or platform.machine())
    text += (u'\n\nالمحرك من مشروع NuvioTV برخصة GPL-3.0. الرخص والمصدر في ملفات هذي الإضافة: LICENSE.txt و SOURCE.txt.'
             if arabic else u'\n\nThe engine is from the NuvioTV project, GPL-3.0. Its licences and source are in this add-on\'s files: LICENSE.txt and SOURCE.txt.')
    xbmcgui.Dialog().ok(addon.getAddonInfo('name'), text)


if __name__ == '__main__':
    main()
