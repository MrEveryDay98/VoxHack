"""Make the compass textures (mods/nhv/textures):
  nhv_compass.png        the 360-degree strip the compass scrolls: north in
                         the middle, east to its right; 2 pixels a degree
  nhv_compass_frame.png  the dark band behind it, fading out at the ends
  nhv_compass_mark.png   the little marker at the middle (where you look)
"""
import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "game", "nethackvoxel", "mods", "nhv", "textures")
FONT = os.path.join(HERE, "..", "game", "nethackvoxel", "mods", "nhv", "fonts", "nhv_retro.ttf")

PX = 3            # pixels a degree
W, H = 360 * PX, 48
GOLD = (232, 214, 160, 255)
DIM = (200, 200, 200, 210)


def strip():
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.fontmode = "1"  # (crisp pixels: no smoothing)
    # (the messages' font, at its own pixel size: theme.lua's FONT_PX)
    big = ImageFont.truetype(FONT, 28)  # (twice the size: still crisp)
    small = big
    # degree 0 (north) is the middle of the image; east (+90) to its right
    def x_of(deg):
        return (W // 2 + deg * PX) % W

    labels = {0: "N", 90: "E", 180: "S", 270: "W", 45: "NE", 135: "SE", 225: "SW", 315: "NW"}
    for deg in range(0, 360, 15):
        x = x_of(deg)
        if deg in labels:
            text = labels[deg]
            font = big if deg % 90 == 0 else small
            w = d.textlength(text, font=font)
            y = 10
            col = GOLD if deg % 90 == 0 else DIM
            for xx in (x - w / 2, x - w / 2 - W, x - w / 2 + W):  # (wraps round)
                d.text((round(xx), y), text, font=font, fill=col)
        else:
            d.rectangle([x - 1, 19, x + 1, 29], fill=DIM)
    return im


def frame():
    fw, fh = 520, 48
    im = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
    px = im.load()
    for x in range(fw):
        # (faded out toward both ends)
        edge = min(x, fw - 1 - x) / 80.0
        a = int(150 * max(0.0, min(1.0, edge)))
        for y in range(fh):
            px[x, y] = (10, 10, 16, a)
        for y in (0, fh - 1):
            px[x, y] = (232, 214, 160, int(a * 0.9))
    return im


def mark():
    im = Image.new("RGBA", (15, 9), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.polygon([(0, 0), (14, 0), (7, 8)], fill=GOLD)
    return im


if __name__ == "__main__":
    strip().save(os.path.join(OUT, "nhv_compass.png"))
    frame().save(os.path.join(OUT, "nhv_compass_frame.png"))
    mark().save(os.path.join(OUT, "nhv_compass_mark.png"))
    print("written to", os.path.normpath(OUT))
