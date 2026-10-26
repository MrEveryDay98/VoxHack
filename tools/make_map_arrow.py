"""Make the big map's facing arrow (mods/nhv/textures):
  nhv_map_arrow_NN.png   the arrow turned NN * 360/STEPS degrees clockwise
                         from pointing up (north); hud.lua shows the one
                         nearest to where you look, out beside your square

HUD pictures can't be turned by any angle, so each angle is its own
picture (a few, fixed: switching between them makes no new textures).

    python tools/make_map_arrow.py
"""
import math
import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "game", "nethackvoxel", "mods", "nhv", "textures")

STEPS = 32
SIZE = 24
GOLD = (255, 208, 64, 255)
EDGE = (0, 0, 0, 255)
# the arrow pointing up, in pixels from the middle (x right, y down)
SHAPE = [(0, -9), (7, 3), (2, 1), (2, 8), (-2, 8), (-2, 1), (-7, 3)]


def arrow(step):
    a = math.radians(step * 360 / STEPS)
    c, s = math.cos(a), math.sin(a)
    mid = SIZE / 2
    pts = [(mid + x * c - y * s, mid + x * s + y * c) for x, y in SHAPE]
    im = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.polygon(pts, fill=GOLD, outline=EDGE)
    # (a dark rim one pixel out, so it reads over any map square)
    rim = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    px, rp = im.load(), rim.load()
    for y in range(SIZE):
        for x in range(SIZE):
            if px[x, y][3] == 0 and any(
                    0 <= x + dx < SIZE and 0 <= y + dy < SIZE and px[x + dx, y + dy][3]
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                rp[x, y] = EDGE
    return Image.alpha_composite(rim, im)


def main():
    for k in range(STEPS):
        arrow(k).save(os.path.join(OUT, "nhv_map_arrow_%02d.png" % k))
    print("wrote %d arrows to %s" % (STEPS, os.path.normpath(OUT)))


if __name__ == "__main__":
    main()
