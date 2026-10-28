#!/usr/bin/env python3
"""Install the DexHub artwork from render_branding.swift into a Kodi checkout.

Usage: install_branding.py KODI_SOURCE RENDERED_FOLDER
Replaces the tvOS asset catalogue's app icon (three parallax layers), top shelf
images and launch image, and Kodi's splash, so launch hands over to the app
without a change of picture.
"""
import json
import shutil
import subprocess
import sys
from pathlib import Path

source, rendered = map(Path, sys.argv[1:3])
catalog = source / 'xbmc/platform/darwin/tvos/Assets.xcassets'
brand = catalog / 'Assets.brandassets'
if not brand.is_dir():
    raise SystemExit('Kodi tvOS asset catalogue not found: ' + str(catalog))
INFO = {'version': 1, 'author': 'xcode'}


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + '\n')


def imageset(folder, image, scale):
    """One supplied scale; the generator derives the other one."""
    if folder.exists():
        shutil.rmtree(folder)
    folder.mkdir(parents=True)
    other = '1x' if scale == '2x' else '2x'
    names = {'1x': 'image.png', '2x': 'image@2x.png'}
    shutil.copyfile(image, folder / names[scale])
    size = subprocess.check_output(['sips', '-g', 'pixelWidth', '-g', 'pixelHeight', str(image)], text=True).split()
    width, height = int(size[-3]), int(size[-1])
    factor = 2 if scale == '1x' else 0.5
    subprocess.run(['sips', '--resampleHeightWidth', str(int(height * factor)), str(int(width * factor)), str(image),
                    '--out', str(folder / names[other])], check=True, stdout=subprocess.DEVNULL)
    write(folder / 'Contents.json', {'images': [{'idiom': 'tv', 'filename': names[scale], 'scale': scale},
                                               {'idiom': 'tv', 'filename': names[other], 'scale': other}],
                                    'info': INFO})


def stack(name, width, height, scale):
    folder = brand / (name + '.imagestack')
    if folder.exists():
        shutil.rmtree(folder)
    layers = []
    for layer in ('front', 'middle', 'back'):
        title = layer.capitalize() + '.imagestacklayer'
        imageset(folder / title / 'Content.imageset', rendered / f'{name}-{layer}.png', scale)
        write(folder / title / 'Contents.json', {'info': INFO})
        layers.append({'filename': title})
    write(folder / 'Contents.json', {'layers': layers, 'info': INFO,
                                     'properties': {'canvasSize': {'width': width, 'height': height}}})


# The Home screen icon is drawn at 2x (800x480); the App Store icon at 1x (1280x768).
stack('icon', 400, 240, '2x')
stack('icon_appstore', 1280, 768, '1x')
imageset(brand / 'topshelf_wide.imageset', rendered / 'topshelf_wide.png', '1x')
imageset(brand / 'topshelf.imageset', rendered / 'topshelf.png', '1x')

launch = catalog / 'LaunchImage.launchimage'
# Kodi links this image to media/applaunch_screen.png; replace the link, not its target.
(launch / 'applaunch_screen.png').unlink(missing_ok=True)
shutil.copyfile(rendered / 'launch.png', launch / 'applaunch_screen.png')
subprocess.run(['sips', '--resampleHeightWidth', '2160', '3840', str(rendered / 'launch.png'),
                '--out', str(launch / 'applaunch_screen@2x.png')], check=True, stdout=subprocess.DEVNULL)

subprocess.run(['sips', '-s', 'format', 'jpeg', '-s', 'formatOptions', '90', str(rendered / 'launch.png'),
                '--out', str(source / 'media/splash.jpg')], check=True, stdout=subprocess.DEVNULL)
print('DexHub artwork installed in', source)
