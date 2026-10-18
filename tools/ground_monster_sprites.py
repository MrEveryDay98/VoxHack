"""Stand the monster sprites on the ground (nhv_tiles.png, edited in place).

Monsters are drawn with the bottom of their 16x16 cell on the floor, so a
picture with empty rows under it seems to hover. This moves each monster's
picture down until its lowest pixel is on the cell's bottom row. Left alone:
monsters that fly or float, cling to the ceiling (NetHack's M1_FLY and
M1_CLING) or swim (eels and the like) - they aren't standing on anything.

usage: python -I tools/ground_monster_sprites.py [--dry-run]
"""
import os
import re
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
TILES = os.path.join(ROOT, "game", "nethackvoxel", "mods", "nhv_tiles")
SHEET = os.path.join(TILES, "textures", "nhv_tiles.png")
NAMES = os.path.join(TILES, "tilenames.lua")
MONSTERS_H = os.path.join(ROOT, "external", "nethack", "include", "monsters.h")
TS = 16
SKIP_CLASSES = {"S_EEL"}  # (swimmers)
# NetHack says these fly, but they're pictured standing (winged humanoids,
# demon lords, dragons...): grounded all the same
GROUNDED_CLASSES = {"S_DRAGON", "S_DEMON", "S_HUMAN", "S_VAMPIRE", "S_HUMANOID",
                    "S_GIANT", "S_MIMIC", "S_GREMLIN", "S_JABBERWOCK"}
GROUNDED = {"Angel", "Archon", "Medusa", "Death", "Famine", "Pestilence",
            "wumpus", "Juiblex", "Wizard of Yendor"}
FLOATING = {"djinni"}  # (in a grounded class, but it floats)


def nethack_monsters():
    """name -> (class, set of M1 flags), from NetHack's monsters.h"""
    src = open(MONSTERS_H, encoding="latin-1").read()
    out = {}
    for block in re.split(r"\n\s*MON\(", src)[1:]:
        # (NAM("x"), or NAMS("male", "female", "neutral"): any of them)
        m = re.match(r'\s*NAMS?\(([^)]*)\)', block)
        c = re.search(r"\b(S_[A-Z_]+)\b", block)
        if m and c:
            info = (c.group(1), set(re.findall(r"\bM1_[A-Z_]+\b", block)))
            for name in re.findall(r'"([^"]+)"', m.group(1)):
                out[name] = info
    return out


def main():
    dry = "--dry-run" in sys.argv
    src = open(NAMES, encoding="utf-8").read()
    cols = int(re.search(r"cols = (\d+)", src).group(1))
    count = int(re.search(r"monsters = (\d+)", src).group(1))

    # (the tables by their exact names: "sheet_names" holds "names" too)
    def table(name):
        return src.split("\n  " + name + " = {", 1)[1].split("}", 1)[0]

    names = dict((int(k), v) for k, v in re.findall(r'\[(\d+)\] = "([^"]*)"', table("names")))
    sheet = dict((int(k), int(v)) for k, v in re.findall(r"\[(\d+)\] = (\d+)", table("sheet")))
    mons = nethack_monsters()
    im = Image.open(SHEET).convert("RGBA")
    done, skipped, unknown, moved = set(), [], [], 0
    for tile in range(count):
        name = names.get(tile, "").split(",")[0]
        s = sheet.get(tile, tile)
        if s in done:
            continue
        done.add(s)
        info = mons.get(name)
        if not info:
            unknown.append(name)
            continue
        cls, m1 = info
        airborne = ("M1_FLY" in m1 or "M1_CLING" in m1) and not (
            cls in GROUNDED_CLASSES or name in GROUNDED)
        if airborne or name in FLOATING or cls in SKIP_CLASSES:
            skipped.append(name)
            continue
        x0, y0 = (s % cols) * TS, (s // cols) * TS
        cell = im.crop((x0, y0, x0 + TS, y0 + TS))
        box = cell.getchannel("A").getbbox()
        if not box:
            continue
        gap = TS - box[3]  # (empty rows under the picture)
        if gap <= 0:
            continue
        moved += 1
        if not dry:
            shifted = Image.new("RGBA", (TS, TS), (0, 0, 0, 0))
            shifted.paste(cell, (0, gap))
            im.paste(shifted, (x0, y0))
    if not dry:
        im.save(SHEET)
    print("%s %d monster cells; left alone (fly, cling, swim): %s"
          % ("would move" if dry else "moved", moved, ", ".join(sorted(set(skipped)))))
    if unknown:
        print("not in monsters.h (left alone):", ", ".join(sorted(set(unknown))))


if __name__ == "__main__":
    main()
