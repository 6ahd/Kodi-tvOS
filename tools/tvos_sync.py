#!/usr/bin/env python3
"""Bring a new general Dex Hub add-on or skin to Apple TV.

Usage: tvos_sync.py BASE OURS THEIRS OUT VERSION
  BASE    the general release the current Apple TV copy was made from (zip or folder)
  OURS    the current Apple TV copy (zip or folder; e.g. the one in the released IPA)
  THEIRS  the new general release (zip)
  OUT     folder to write the new Apple TV copy into (its top folder is the add-on id)
  VERSION plain numeric version for the result (the repository rejects letters)

Every file is merged three ways: what the general line changed since BASE is
applied on top of the Apple TV copy, so its own changes (players, phone
files, performance work) stay. General names are first renamed to the Apple
TV ones (plugin.video.dexhub.tvos, skin.dexhub.tvos, dexhub.tvos.assetroot).
XML is compared in one formatting, since the Apple TV files may be minified.
Exit status 2 and a list when a file has conflicts it cannot settle.
"""
import re
import shutil
import subprocess
import sys
import tempfile
import xml.dom.minidom as minidom
import zipfile
from pathlib import Path

TEXT = {'.py', '.xml', '.po', '.txt', '.json', '.html', '.js', '.css', '.md', '.sh', ''}


def rename(text):
    text = re.sub(r'plugin\.video\.dexhub(?!\.tvos)', 'plugin.video.dexhub.tvos', text)
    text = re.sub(r'skin\.dexhub(?!\.tvos)', 'skin.dexhub.tvos', text)
    return re.sub(r'dexhub\.assetroot', 'dexhub.tvos.assetroot', text)


def tree(source, scratch, name):
    """A folder holding the add-on's files, unpacked from a zip when needed."""
    source = Path(source)
    if source.is_dir():
        return source
    target = Path(scratch) / name
    with zipfile.ZipFile(source) as archive:
        archive.extractall(target)
    tops = [p for p in target.iterdir() if p.is_dir()]
    return tops[0] if len(tops) == 1 else target


def files(root):
    return {str(p.relative_to(root)): p for p in root.rglob('*')
            if p.is_file() and '__pycache__' not in p.parts and p.suffix != '.pyc' and p.name != '.DS_Store'}


def pretty(text):
    """One formatting for any XML (indented, comments kept), or None if it does not parse."""
    declaration = re.match(r'\s*<\?xml[^>]*\?>', text)
    body = text[declaration.end():] if declaration else text
    try:
        document = minidom.parseString(('<dhwrap>' + body + '</dhwrap>').encode())
    except Exception:
        return None

    def strip(node):
        for child in list(node.childNodes):
            if child.nodeType == child.TEXT_NODE and not child.data.strip():
                node.removeChild(child)
            else:
                strip(child)
    strip(document)
    lines = document.documentElement.toprettyxml(indent='\t').splitlines()[1:-1]
    head = '<?xml version="1.0" encoding="UTF-8"?>\n' if declaration else ''
    return head + '\n'.join(line[1:] for line in lines) + '\n'


def read(path, xml):
    data = path.read_bytes()
    try:
        text = data.decode('utf-8')
    except UnicodeDecodeError:
        return None
    return text


def main():
    base_src, ours_src, theirs_src, out, version = sys.argv[1:6]
    with tempfile.TemporaryDirectory() as scratch:
        base, ours, theirs = (tree(s, scratch, n) for s, n in ((base_src, 'base'), (ours_src, 'ours'), (theirs_src, 'theirs')))
        b, o, t = files(base), files(ours), files(theirs)
        addon_id = ours.name
        target = Path(out) / addon_id
        if target.exists():
            shutil.rmtree(target)
        conflicts, settled, counts = [], [], {'merged': 0, 'theirs': 0, 'ours': 0, 'added': 0, 'removed': 0}
        for name in sorted(set(b) | set(o) | set(t)):
            dest = target / name
            in_b, in_o, in_t = name in b, name in o, name in t
            suffix = Path(name).suffix.lower()
            if not in_o and in_t:          # new in the general line
                write(dest, t[name], suffix)
                counts['added'] += 1
                continue
            if in_o and not in_t:
                if in_b:                   # the general line removed it
                    counts['removed'] += 1
                    continue
                shutil.copy2(o[name], dest_dir(dest))   # Apple TV only
                counts['ours'] += 1
                continue
            if not in_o:
                continue
            if suffix not in TEXT:         # pictures, fonts: newest general copy if it changed
                changed = not in_b or b[name].read_bytes() != t[name].read_bytes()
                shutil.copy2(t[name] if changed else o[name], dest_dir(dest))
                counts['theirs' if changed else 'ours'] += 1
                continue
            texts = [read(p, suffix == '.xml') for p in ((b[name] if in_b else t[name]), o[name], t[name])]
            if None in texts:
                shutil.copy2(t[name], dest_dir(dest))
                counts['theirs'] += 1
                continue
            base_text, ours_text, theirs_text = rename(texts[0]), texts[1], rename(texts[2])
            if suffix == '.xml':
                shaped = [pretty(x) for x in (base_text, ours_text, theirs_text)]
                if None not in shaped:
                    if shaped[0] == shaped[1]:     # no Apple TV change: the general file as written
                        dest_dir(dest).write_text(theirs_text, encoding='utf-8')
                        counts['theirs'] += 1
                        continue
                    base_text, ours_text, theirs_text = shaped
            if base_text == ours_text:
                dest_dir(dest).write_text(theirs_text, encoding='utf-8')
                counts['theirs'] += 1
                continue
            if base_text == theirs_text:
                dest_dir(dest).write_text(ours_text, encoding='utf-8')
                counts['ours'] += 1
                continue
            merged, clashes = merge(scratch, base_text, ours_text, theirs_text)
            if clashes:
                merged = resolve(merged)
                if '<<<<<<< appletv' in merged:
                    conflicts.append((name, clashes))
                else:
                    settled.append((name, clashes))
            if suffix == '.xml' and pretty(merged) is None:
                conflicts.append((name, 'XML does not parse after merging'))
            dest_dir(dest).write_text(merged, encoding='utf-8')
            counts['merged'] += 1
        set_version(target, version)
        apple_tv_fixups(target, ours)
        print('%s %s: %s' % (addon_id, version, ', '.join('%s %d' % kv for kv in counts.items())))
        for name, clashes in settled:
            print('  settled %s (%d conflict%s)' % (name, clashes, '' if clashes == 1 else 's'))
        for name, clashes in conflicts:
            print('  CONFLICT %s (%s)' % (name, clashes))
        sys.exit(2 if conflicts else 0)


def dest_dir(dest):
    dest.parent.mkdir(parents=True, exist_ok=True)
    return dest


def write(dest, source, suffix):
    if suffix in TEXT:
        try:
            dest_dir(dest).write_text(rename(source.read_text(encoding='utf-8')), encoding='utf-8')
            return
        except UnicodeDecodeError:
            pass
    shutil.copy2(source, dest_dir(dest))


NAMES = re.compile(r'<(?:variable|expression|include|constant)\s+name="([^"]+)"|^msgctxt\s+"([^"]+)"', re.M)


def rebase(base, ours, theirs):
    """Replay the Apple TV copy's edits to a conflicting block onto the general one.

    Each run of lines the Apple TV copy changed is replaced where the same
    run still stands in the general block; a run the general line rewrote is
    left as the general line wrote it. Lines both sides only added are kept
    from both, unless the general block already defines the same names.
    """
    import difflib
    b, o, t = base.splitlines(True), ours.splitlines(True), theirs.splitlines(True)
    if not b:
        own = set(n for pair in NAMES.findall(ours) for n in pair if n)
        general = set(n for pair in NAMES.findall(theirs) for n in pair if n)
        return theirs if own & general else ours + theirs
    result = t[:]
    for tag, i1, i2, j1, j2 in reversed(difflib.SequenceMatcher(None, b, o, autojunk=False).get_opcodes()):
        if tag == 'equal' or i1 == i2:
            continue
        run = b[i1:i2]
        for k in range(len(result) - len(run) + 1):
            if result[k:k + len(run)] == run:
                result[k:k + len(run)] = o[j1:j2]
                break
    return ''.join(result)


def resolve(text):
    """Settle every diff3 conflict block in text with rebase()."""
    pattern = re.compile(r'<<<<<<< appletv\n(.*?)\|\|\|\|\|\|\| base\n(.*?)=======\n(.*?)>>>>>>> general\n', re.S)
    return pattern.sub(lambda m: rebase(m.group(2), m.group(1), m.group(3)), text)


def merge(scratch, base, ours, theirs):
    paths = []
    for label, text in (('ours', ours), ('base', base), ('theirs', theirs)):
        path = Path(scratch) / ('merge-' + label)
        path.write_text(text, encoding='utf-8')
        paths.append(str(path))
    result = subprocess.run(['git', 'merge-file', '-p', '--diff3', '-L', 'appletv', '-L', 'base', '-L', 'general'] + paths,
                            capture_output=True, text=True)
    return result.stdout, max(0, result.returncode) if result.returncode < 128 else 1


VIDEO_WINDOW = re.compile(r'[ \t]*<control type="videowindow">(?:(?!<control\b).)*?</control>\n?', re.S)


def apple_tv_fixups(target, ours):
    """What the Apple TV copy keeps whatever the general line does."""
    descriptor = target / 'addon.xml'
    text = descriptor.read_text(encoding='utf-8')
    names = {'plugin.video.dexhub.tvos': 'Dex Hub (Apple TV)', 'skin.dexhub.tvos': 'Dex Hub Skin (Apple TV)'}
    if target.name in names:
        text = re.sub(r'(<addon\b[^>]*\sname=")[^"]*(")', lambda m: m.group(1) + names[target.name] + m.group(2), text, count=1)
    if target.name == 'skin.dexhub.tvos':
        # The skin needs this exact add-on and the Apple TV player controls.
        plugin = target.parent / 'plugin.video.dexhub.tvos' / 'addon.xml'
        version = re.search(r'<addon\b[^>]*\bversion="([^"]+)"', plugin.read_text(encoding='utf-8')).group(1) if plugin.exists() else None
        if version:
            text = re.sub(r'<import addon="plugin\.video\.dexhub\.tvos"[^>]*/>',
                          '<import addon="plugin.video.dexhub.tvos" version="%s"/>' % version, text)
        if 'script.dexhub.tvos.players' not in text:
            text = re.sub(r'(<import addon="plugin\.video\.dexhub\.tvos"[^>]*/>)',
                          r'\1\n\t\t<import addon="script.dexhub.tvos.players" version="1.0.15"/>', text, count=1)
        # Card trailers (videowindow controls) stay off on Apple TV: the GPU
        # cannot keep up. Keep only the ones the Apple TV copy itself has.
        home = target / 'xml/Home.xml'
        kept = set(re.findall(r'<control type="videowindow">.*?<visible>(.*?)</visible>', (Path(ours) / 'xml/Home.xml').read_text(encoding='utf-8'), re.S))
        page = home.read_text(encoding='utf-8')
        page = VIDEO_WINDOW.sub(lambda m: m.group(0) if any(v in m.group(0) for v in kept) else '', page)
        home.write_text(page, encoding='utf-8')
    descriptor.write_text(text, encoding='utf-8')


def set_version(target, version):
    descriptor = target / 'addon.xml'
    text = descriptor.read_text(encoding='utf-8')
    text = re.sub(r'(<addon\b[^>]*\bversion=")[^"]*(")', lambda m: m.group(1) + version + m.group(2), text, count=1)
    descriptor.write_text(text, encoding='utf-8')


if __name__ == '__main__':
    main()
