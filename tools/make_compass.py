"""Make the compass textures (mods/nhv/textures):
  nhv_compass.png        the 360-degree strip the compass scrolls: north in
                         the middle, east to its right; 3 pixels a degree
  nhv_compass_frame.png  the dark band behind it, fading out at the ends
  nhv_compass_mark.png   the little marker at the middle (where you look)
and the same, small, for retro mode's small screens (hud.lua):
  nhv_compass_small.png, nhv_compass_small_frame.png,
  nhv_compass_small_mark.png - a pixel a degree, the font at its own size
"""
import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "game", "nethackvoxel", "mods", "nhv", "textures")
FONT = os.path.join(HERE, "..", "game", "nethackvoxel", "mods", "nhv", "fonts", "nhv_retro.ttf")

PX = 3            # pixels a degree
W, H = 360 * PX, 48
# (retro mode's: small() below)
SMALL_PX, SMALL_H = 1, 24
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


def small():
    """the strip for small screens: a pixel a degree, the font at 14 px"""
    w = 360 * SMALL_PX
    im = Image.new("RGBA", (w, SMALL_H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.fontmode = "1"
    font = ImageFont.truetype(FONT, 14)
    labels = {0: "N", 90: "E", 180: "S", 270: "W", 45: "NE", 135: "SE", 225: "SW", 315: "NW"}
    for deg in range(0, 360, 15):
        x = (w // 2 + deg * SMALL_PX) % w
        if deg in labels:
            text = labels[deg]
            tw = d.textlength(text, font=font)
            col = GOLD if deg % 90 == 0 else DIM
            for xx in (x - tw / 2, x - tw / 2 - w, x - tw / 2 + w):
                d.text((round(xx), 5), text, font=font, fill=col)
        else:
            d.line([x, 10, x, 14], fill=DIM)
    return im


def small_frame():
    fw, fh = 180, 24
    im = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
    px = im.load()
    for x in range(fw):
        a = int(150 * max(0.0, min(1.0, min(x, fw - 1 - x) / 28.0)))
        for y in range(fh):
            px[x, y] = (10, 10, 16, a)
        for y in (0, fh - 1):
            px[x, y] = (232, 214, 160, int(a * 0.9))
    return im


def small_mark():
    im = Image.new("RGBA", (7, 4), (0, 0, 0, 0))
    ImageDraw.Draw(im).polygon([(0, 0), (6, 0), (3, 3)], fill=GOLD)
    return im


if __name__ == "__main__":
    small().save(os.path.join(OUT, "nhv_compass_small.png"))
    small_frame().save(os.path.join(OUT, "nhv_compass_small_frame.png"))
    small_mark().save(os.path.join(OUT, "nhv_compass_small_mark.png"))
    strip().save(os.path.join(OUT, "nhv_compass.png"))
    frame().save(os.path.join(OUT, "nhv_compass_frame.png"))
    mark().save(os.path.join(OUT, "nhv_compass_mark.png"))
    print("written to", os.path.normpath(OUT))
