"""Read native/kodi-22.0rc1-dexhub.patch: the whole text, and new files' contents."""
from pathlib import Path

PATCH = Path(__file__).resolve().parents[1] / 'native/kodi-22.0rc1-dexhub.patch'
text = PATCH.read_text()


def new_file(path):
    """Contents of a file the patch adds, e.g. xbmc/platform/darwin/tvos/TVOSAetherPlayer.mm."""
    section = text.split('diff --git a/' + path + ' b/' + path + '\n', 1)[1].split('\ndiff --git ', 1)[0]
    if '\nnew file mode' not in '\n' + section:
        raise AssertionError(path + ' is not a new file in the patch')
    body = section.split('\n@@', 1)[1].split('\n', 1)[1]
    return ''.join(line[1:] + '\n' for line in body.split('\n') if line.startswith('+'))
