"""Retro mode's dithered fades (theme.veil): nhv_dither_screen_<n>.png,
n = 1..15 - a 128x128 tile of a 4x4 ordered (Bayer) dither, white where
the fade covers (n of each 16 pixels), clear elsewhere.

    py -3 tools/make_dither_screen.py
"""
import os
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), '..', 'game', 'nethackvoxel', 'mods', 'nhv_tiles', 'textures')
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
N = 128

for n in range(1, 16):
    im = Image.new('RGBA', (N, N), (0, 0, 0, 0))
    px = im.load()
    for y in range(N):
        for x in range(N):
            if BAYER[y % 4][x % 4] < n:
                px[x, y] = (255, 255, 255, 255)
    im.save(os.path.join(OUT, 'nhv_dither_screen_%d.png' % n))
print('ok')
