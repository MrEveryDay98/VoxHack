"""Placeholder art for the title screen (replace the files with real art).

    python tools/make_title_placeholders.py

Writes game/nethackvoxel/mods/nhv_tiles/textures/:
  nhv_title_logo.png  "VOXHACK" in the game's pixel font (transparent)
  nhv_title_bg.png    a dim brick wall (the screen's background)
Any PNGs with those names work: the logo is drawn 4:1 (wide), the
background stretched over the whole screen.
"""
import os
import random

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "game", "nethackvoxel", "mods", "nhv_tiles", "textures")
FONT = os.path.join(ROOT, "game", "nethackvoxel", "mods", "nhv", "fonts", "nhv_retro.ttf")


def logo():
    w, h = 256, 64
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    big = ImageFont.truetype(FONT, 42)
    small = ImageFont.truetype(FONT, 14)
    for text, font, y, col in (("VOXHACK", big, 0, (255, 210, 90, 255)),
                               ("BASED ON NETHACK", small, 46, (120, 200, 255, 255))):
        tw = d.textlength(text, font=font)
        x = (w - tw) // 2
        d.text((x + 2, y + 2), text, font=font, fill=(60, 20, 0, 255))  # shadow
        d.text((x, y), text, font=font, fill=col)
    return im


def background():
    w, h = 160, 90
    rnd = random.Random(7)
    im = Image.new("RGBA", (w, h), (10, 10, 16, 255))
    px = im.load()
    bw, bh = 16, 8
    for y in range(h):
        for x in range(w):
            row = y // bh
            ox = (bw // 2) if row % 2 else 0
            mortar = y % bh == 0 or (x + ox) % bw == 0
            # darker toward the edges, like torchlight in the middle
            cx, cy = (x - w / 2) / (w / 2), (y - h / 2) / (h / 2)
            light = max(0.15, 1 - (cx * cx + cy * cy) * 0.75)
            if mortar:
                c = (8, 8, 12)
            else:
                n = rnd.randint(-6, 6)
                c = (34 + n, 36 + n, 52 + n)
            px[x, y] = (int(c[0] * light), int(c[1] * light), int(c[2] * light), 255)
    return im


def main():
    os.makedirs(OUT, exist_ok=True)
    logo().save(os.path.join(OUT, "nhv_title_logo.png"))
    background().save(os.path.join(OUT, "nhv_title_bg.png"))
    print("nhv_title_logo.png nhv_title_bg.png")


if __name__ == "__main__":
    main()
