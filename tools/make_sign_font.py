"""Letters for the shop signs (signs.lua): each printable ASCII character
of the game's pixel font, 8x12, in white (nhv_sf_<code>.png) and as its
dark shadow (nhv_sfs_<code>.png), in mods/nhv/textures.

    python -I tools/make_sign_font.py
"""
import os
from PIL import Image, ImageFont, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NHV = os.path.join(ROOT, "game", "nethackvoxel", "mods", "nhv")
font = ImageFont.truetype(os.path.join(NHV, "fonts", "nhv_retro.ttf"), 14)
for c in range(33, 127):
    for name, col in (("nhv_sf_%d.png", (255, 255, 255, 255)), ("nhv_sfs_%d.png", (40, 16, 0, 255))):
        im = Image.new("RGBA", (8, 12), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        d.fontmode = "1"
        d.text((0, -1), chr(c), font=font, fill=col)
        im.save(os.path.join(NHV, "textures", name % c), optimize=True)
