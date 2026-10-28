"""v21: the Kodi layer above Aether redraws only on change."""
from kodi_patch import new_file, text as adapter
native = new_file('xbmc/platform/darwin/tvos/TVOSAetherPlayer.mm')
header = new_file('xbmc/platform/darwin/tvos/TVOSAetherPlayer.h')
assert 'unsigned int DexAetherRedrawRevision();' in header
assert 'unsigned int DexAetherRedrawRevision() {' in native
assert native.count('RequestRedraw();') >= 5
assert 'ActiveText(state)' in native and native.count('for (NSDictionary* cue in state.cues)') == 1
assert 'wait = 250;' in native
assert '// DexHub redraw on change v21.' in adapter
assert '// DexHub idle frame pacing v21.' in adapter
assert '|| appPlayer->GetCurrentPlayer() == "Aether")\n    MarkDirtyRegion' not in adapter
print('v21 idle checks passed')
# v21.1: VideoPlayer order. Started is sent once, from OpenFile after the
# thread starts; AV started follows the first frame.
assert native.count('m_callback.OnPlayBackStarted(') == 1
open_file = native.split('bool CTVOSAetherPlayer::OpenFile', 1)[1].split('bool CTVOSAetherPlayer::CloseFile', 1)[0]
assert open_file.index('Create();') < open_file.index('m_callback.OnPlayBackStarted(started);')
assert native.count('m_callback.OnAVStarted(') == 1
print('v21.1 callback order checks passed')
# v21.2: external subtitles carry Kodi's own file-name labels (name, language, flags)
assert '#include "Util.h"' in native
assert native.count('CUtil::GetExternalStreamDetailsFromFilename(') == 1
assert 'm_state->externalPaths.push_back(translated)' in native
assert 'info.flags = static_cast<StreamFlags>(track.label.flag);' in native
print('v21.2 subtitle label checks passed')
