"""Give every NetHack tile its own cell in the sprite sheet again (one-time
migration, keeping every edit made to the sheet).

The sheet once held each distinct sprite only once (identical male/female
pairs shared a cell: tiles2png.py). This lays it out NetHack's way again -
cell n is NetHack's tile n (monsters.txt, objects.txt, other.txt; statues
are still drawn from their monster's cell) - so a male and a female can be
drawn differently. Each new cell starts as a copy of the sprite that tile
used, edits and all; both halves of a shared pair get the same picture.

It also moves what pointed at the old cells: custom blocks' "sheet" in
mods/nhv_blocks/blocks.json, and holds.lua's engulf frame.

    py -3 tools/restore_tile_layout.py          (check only)
    py -3 tools/restore_tile_layout.py --write
"""
import json
import os
import re
import sys

from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
MODS = os.path.join(ROOT, 'game', 'nethackvoxel', 'mods')
TILES = os.path.join(MODS, 'nhv_tiles')
SHEET = os.path.join(TILES, 'textures', 'nhv_tiles.png')
LUA = os.path.join(TILES, 'tilenames.lua')
BLOCKS = os.path.join(MODS, 'nhv_blocks', 'blocks.json')
HOLDS = os.path.join(MODS, 'nhv', 'holds.lua')
TP = 16


def lua_str(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


def section(text, name):
    m = re.search(r'\n  ' + name + r' = \{\n(.*?)\n  \},', text, re.S)
    return m.group(1)


def read_meta():
    text = open(LUA, encoding='utf-8').read()
    meta = {k: int(re.search(r'\n  ' + k + r' = (\d+),', text).group(1))
            for k in ('count', 'monsters', 'cols', 'rows', 'sheet_count')}
    meta['sheet'] = {int(a): int(b) for a, b in re.findall(r'\[(\d+)\] = (\d+),', section(text, 'sheet'))}
    meta['names'] = {int(a): json.loads(b) for a, b in
                     re.findall(r'\[(\d+)\] = ("(?:[^"\\]|\\.)*"),', section(text, 'names'))}
    meta['statue'] = {int(a) for a in re.findall(r'\[(\d+)\] = true,', section(text, 'statue'))}
    return meta


def cell_name(name):
    for sex in ('male', 'female'):
        if name.endswith(',' + sex):
            return name[:-len(sex) - 1] + ' (' + sex + ')'
    return name


def main():
    write = '--write' in sys.argv
    meta = read_meta()
    count, nmon, cols = meta['count'], meta['monsters'], meta['cols']
    n = count - nmon  # (the statues are the last nmon tiles)
    assert all(t >= n for t in meta['statue']) and len(meta['statue']) == nmon, 'statues not last'
    assert len(meta['names']) == count and len(meta['sheet']) == count
    old = Image.open(SHEET).convert('RGBA')
    ocols = old.size[0] // TP
    rows = (n + cols - 1) // cols
    new = Image.new('RGBA', (cols * TP, rows * TP), (0, 0, 0, 0))
    for t in range(n):
        s = meta['sheet'][t]
        x, y = (s % ocols) * TP, (s // ocols) * TP
        new.paste(old.crop((x, y, x + TP, y + TP)), ((t % cols) * TP, (t // cols) * TP))
    # old cell -> new cell: the first tile that used it (a pair's male)
    moved = {}
    for t in range(n):
        moved.setdefault(meta['sheet'][t], t)
    # (every new cell is what its tile showed before)
    for t in range(n):
        s = meta['sheet'][t]
        a = old.crop(((s % ocols) * TP, (s // ocols) * TP, (s % ocols + 1) * TP, (s // ocols + 1) * TP))
        b = new.crop(((t % cols) * TP, (t // cols) * TP, (t % cols + 1) * TP, (t // cols + 1) * TP))
        assert a.tobytes() == b.tobytes(), t
    used = [meta['sheet'][t] for t in range(n)]
    shared = sum(1 for t in range(n) if used.count(used[t]) > 1)
    print('%d tiles: %d cells (was %d), %d monster tiles were sharing a cell' %
          (count, n, meta['sheet_count'], shared))

    # what pointed at old cells
    blocks = open(BLOCKS, encoding='utf-8', newline='').read()
    changes = []

    def repoint(m):
        changes.append((int(m.group(2)), moved[int(m.group(2))]))
        return m.group(1) + str(moved[int(m.group(2))])
    blocks = re.sub(r'("sheet"\s*:\s*)(\d+)', repoint, blocks)
    holds = open(HOLDS, encoding='utf-8', newline='').read()
    hm = re.search(r'local SWALLOW_SHEET = (\d+)', holds)
    swallow = int(hm.group(1))
    print('blocks.json sheet:', changes, '| holds.lua SWALLOW_SHEET:', swallow, '->', moved[swallow])
    # (the engulf frame's eight cells must still follow one another)
    assert [moved[swallow + i] for i in range(8)] == [moved[swallow] + i for i in range(8)]
    if not write:
        print('(check only: --write to save)')
        return

    new.save(SHEET, optimize=True)
    open(BLOCKS, 'w', encoding='utf-8', newline='').write(blocks)
    holds = holds.replace(hm.group(0), 'local SWALLOW_SHEET = %d' % moved[swallow])
    holds = holds.replace('sheet %d on:' % swallow, 'sheet %d on:' % moved[swallow])
    open(HOLDS, 'w', encoding='utf-8', newline='').write(holds)
    with open(LUA, 'w', encoding='utf-8', newline='\n') as f:
        f.write('-- generated by tools/tiles2png.py (laid out again by tools/restore_tile_layout.py)\n')
        f.write("-- tile = NetHack's tile number; sheet = position in nhv_tiles.png\n")
        f.write('-- (left to right, top to bottom, starting at 0); a tile\'s cell is its own\n')
        f.write('-- number, but for statues (their monster\'s cell, in stone colours)\n')
        f.write('return {\n')
        f.write('  count = %d,\n  monsters = %d,\n  cols = %d,\n  rows = %d,\n' % (count, nmon, cols, rows))
        f.write('  sheet_count = %d,\n' % n)
        f.write('  -- what is at each sheet position\n  sheet_names = {\n')
        for t in range(n):
            f.write('    [%d] = %s,\n' % (t, lua_str(cell_name(meta['names'][t]))))
        f.write('  },\n  -- NetHack tile -> sheet position\n  sheet = {\n')
        for t in range(count):
            f.write('    [%d] = %d,\n' % (t, t if t < n else t - n))
        f.write('  },\n  -- NetHack tiles drawn as statues (stone-coloured)\n  statue = {\n')
        for t in sorted(meta['statue']):
            f.write('    [%d] = true,\n' % t)
        f.write('  },\n  names = {\n')
        for t in range(count):
            f.write('    [%d] = %s,\n' % (t, lua_str(meta['names'][t])))
        f.write('  },\n}\n')
    print('written')


if __name__ == '__main__':
    main()
