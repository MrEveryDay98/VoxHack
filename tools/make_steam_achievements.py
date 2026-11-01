"""The game's achievements, ready to set up in Steamworks (App Admin > Stats
& Achievements > Achievements): dist/steam/achievements/ -

    ACHIEVEMENTS.md      one row each: the API name (the game's own id: what
                         it unlocks on Steam - steam.lua), display name,
                         description, whether to hide it (suggested for the
                         late game's spoilers), and its two icons
    achievements.csv     the same, for a spreadsheet
    <id>.jpg             its icon, 256x256: the achievement's sprite
    <id>_locked.jpg      the same in grey, darker (not yet unlocked)

The list comes from achievements.lua itself (tools/dump_achievements.lua,
run with luajit), the sprites from the sprite sheet (nhv_tiles.png, by
the names in tilenames.lua) - as the game's Achievements screen shows them.
make_steam.py runs this; on its own:

    py -3 -I tools/make_steam_achievements.py
"""
import csv
import json
import os
import re
import subprocess

from PIL import Image, ImageOps

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
MODS = os.path.join(ROOT, 'game', 'nethackvoxel', 'mods')
OUT = os.path.join(ROOT, 'dist', 'steam', 'achievements')
LUAJIT = r'C:\msys64\clang64\bin\luajit.exe'
SIZE, SPRITE = 256, 192
BACK = (20, 20, 24)
# (the late game: hidden on Steam until unlocked, so its names don't spoil it)
HIDDEN = {'invocation', 'amulet', 'endgame', 'astral', 'death', 'famine', 'pestilence'}


def achievements():
    out = subprocess.run([LUAJIT, os.path.join(ROOT, 'tools', 'dump_achievements.lua'),
                          os.path.join(MODS, 'nhv', 'achievements.lua')],
                         capture_output=True, text=True, encoding='utf-8', check=True).stdout
    rows = []
    for line in out.splitlines():
        if line.strip():
            i, name, desc, icon, group = (line.split('\t') + [''] * 5)[:5]
            rows.append({'id': i, 'name': name, 'desc': desc, 'icon': icon, 'group': group})
    return rows


def sheet():
    text = open(os.path.join(MODS, 'nhv_tiles', 'tilenames.lua'), encoding='utf-8').read()
    cols = int(re.search(r'\n  cols = (\d+),', text).group(1))
    body = re.search(r'\n  sheet_names = \{\n(.*?)\n  \},', text, re.S).group(1)
    names = {}
    for i, n in re.findall(r'\[(\d+)\] = ("(?:[^"\\]|\\.)*"),', body):
        names.setdefault(json.loads(n), int(i))
    img = Image.open(os.path.join(MODS, 'nhv_tiles', 'textures', 'nhv_tiles.png')).convert('RGBA')
    return names, cols, img


def icon(img, cols, s):
    x, y = (s % cols) * 16, (s // cols) * 16
    sprite = img.crop((x, y, x + 16, y + 16)).resize((SPRITE, SPRITE), Image.NEAREST)
    out = Image.new('RGBA', (SIZE, SIZE), BACK + (255,))
    out.alpha_composite(sprite, ((SIZE - SPRITE) // 2, (SIZE - SPRITE) // 2))
    return out.convert('RGB')


def main():
    rows = achievements()
    names, cols, img = sheet()
    os.makedirs(OUT, exist_ok=True)
    missing = []
    for a in rows:
        s = names.get(a['icon'], names.get(a['icon'] + ' (male)'))
        if s is None:
            missing.append(a['id'])
            s = 0
        unlocked = icon(img, cols, s)
        unlocked.save(os.path.join(OUT, a['id'] + '.jpg'), quality=95)
        locked = ImageOps.grayscale(unlocked).point(lambda v: int(v * 0.55)).convert('RGB')
        locked.save(os.path.join(OUT, a['id'] + '_locked.jpg'), quality=95)
        a['hidden'] = 'yes' if a['id'] in HIDDEN else ''
    with open(os.path.join(OUT, 'achievements.csv'), 'w', encoding='utf-8', newline='') as f:
        w = csv.writer(f)
        w.writerow(['API name', 'Display name', 'Description', 'Hidden', 'Group', 'Icon', 'Locked icon'])
        for a in rows:
            w.writerow([a['id'], a['name'], a['desc'], a['hidden'], a['group'],
                        a['id'] + '.jpg', a['id'] + '_locked.jpg'])
    with open(os.path.join(OUT, 'ACHIEVEMENTS.md'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('# VoxHack\'s achievements, for Steamworks\n\n')
        f.write('App Admin > Stats & Achievements > Achievements: one "New Achievement" each. '
                'The **API name must be exactly the id below** (the game unlocks it by that name). '
                'Icons: `<id>.jpg` (achieved) and `<id>_locked.jpg` (unachieved), in this folder. '
                '"Hidden" is a suggestion: those name late-game things a new player hasn\'t seen. '
                'Then publish the changes (Publish tab).\n\n')
        f.write('%d achievements.\n' % len(rows))
        group = None
        for a in rows:
            if a['group'] != group:
                group = a['group']
                f.write('\n## %s\n\n| API name | Display name | Description | Hidden |\n|---|---|---|---|\n' % group)
            f.write('| `%s` | %s | %s | %s |\n' % (a['id'], a['name'], a['desc'], a['hidden']))
    print('%s: %d achievements' % (OUT, len(rows)) + (' (no sprite found: %s)' % ', '.join(missing) if missing else ''))


if __name__ == '__main__':
    main()
