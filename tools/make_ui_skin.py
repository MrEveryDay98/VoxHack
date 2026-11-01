"""The HUD skin's default pictures (skin.lua): ui_frame.png, the boxes'
frame - raised grey stone, a gold stud in each corner; ui_slot.png, a slot -
sunk in. Each 24x24, nine 8x8 pieces. Draw your own over them.

    py -3 tools/make_ui_skin.py
"""
import os
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), '..', 'game', 'nethackvoxel', 'mods', 'nhv_tiles', 'textures')
N = 24


def hexc(s):
    return tuple(int(s[i:i + 2], 16) for i in (1, 3, 5)) + (255,)


def bevel(rings_lit, rings_dark, inner):
    """rings from the outside in: (top/left colour, bottom/right colour)"""
    im = Image.new('RGBA', (N, N), hexc(inner))
    px = im.load()
    for d, (lit, dark) in enumerate(zip(rings_lit, rings_dark)):
        for i in range(d, N - d):
            px[i, d] = hexc(lit)            # top
            px[d, i] = hexc(lit)            # left
            px[i, N - 1 - d] = hexc(dark)   # bottom
            px[N - 1 - d, i] = hexc(dark)   # right
        # (the corners where the lit and dark sides meet: half way)
        px[N - 1 - d, d] = hexc(dark)
        px[d, N - 1 - d] = hexc(dark)
    return im


def frame():
    im = bevel(['#000000', '#9A9AA4', '#64646E'], ['#000000', '#3C3C44', '#2A2A30'], '#101014')
    px = im.load()
    for cx, cy in ((0, 0), (1, 0), (0, 1), (1, 1)):
        # a gold stud, its light from the top left
        x0 = 1 if cx == 0 else N - 3
        y0 = 1 if cy == 0 else N - 3
        px[x0, y0] = hexc('#F0D070')
        px[x0 + 1, y0] = hexc('#C89A38')
        px[x0, y0 + 1] = hexc('#C89A38')
        px[x0 + 1, y0 + 1] = hexc('#8A6420')
    return im


def slot():
    return bevel(['#000000', '#26262C', '#1C1C22'], ['#000000', '#5A5A64', '#3A3A42'], '#141418')


frame().save(os.path.join(OUT, 'ui_frame.png'))
slot().save(os.path.join(OUT, 'ui_slot.png'))
print('ok')
