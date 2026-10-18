"""Engraving marks (game/nethackvoxel/mods/nhv_tiles/textures/nhv_engr_*.png).

NetHack's engraving tiles paint the writing over a patch of floor; laid on
the 3D floor that patch shows as a square of another colour. This keeps
only the writing - the yellow marks - on a see-through picture, which the
game lays on the real floor. Run it again after redrawing those tiles.
"""
import os
import re

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
TILES = os.path.join(HERE, "..", "game", "nethackvoxel", "mods", "nhv_tiles")
SHEET = os.path.join(TILES, "textures", "nhv_tiles.png")
NAMES = os.path.join(TILES, "tilenames.lua")
OUT = {"engraving in a room": "nhv_engr_room.png",
       "engraving in a corridor": "nhv_engr_corr.png"}
TS = 16


def is_mark(r, g, b, a):
    # yellow: red and green well up, blue low
    return a >= 128 and r >= 120 and g >= 120 and b <= 110 and min(r, g) - b >= 60


def main():
    src = open(NAMES, encoding="utf-8").read()
    cols = int(re.search(r"cols = (\d+)", src).group(1))

    # (the tables by their exact names: "sheet_names" holds "names" too)
    def table(name):
        return src.split("\n  " + name + " = {", 1)[1].split("}", 1)[0]

    names = dict((v, int(k)) for k, v in re.findall(r'\[(\d+)\] = "([^"]*)"', table("names")))
    sheet = dict((int(k), int(v)) for k, v in re.findall(r"\[(\d+)\] = (\d+)", table("sheet")))
    im = Image.open(SHEET).convert("RGBA")
    for name, fname in OUT.items():
        tile = names[name]
        s = sheet.get(tile, tile)
        x0, y0 = (s % cols) * TS, (s // cols) * TS
        out = Image.new("RGBA", (TS, TS), (0, 0, 0, 0))
        n = 0
        for y in range(TS):
            for x in range(TS):
                px = im.getpixel((x0 + x, y0 + y))
                if is_mark(*px):
                    out.putpixel((x, y), px)
                    n += 1
        path = os.path.join(TILES, "textures", fname)
        out.save(path)
        print("%s: %d marks -> %s" % (name, n, os.path.normpath(path)))


if __name__ == "__main__":
    main()
