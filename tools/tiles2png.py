"""Convert NetHack's vanilla tileset (win/share/*.txt) to per-tile PNGs.

Tile numbering matches glyphmap[].tileidx in the generated tile.c:
monsters.txt, then objects.txt, then other.txt, then one generated
statue tile per monster tile (grayscale copy).

usage: python tiles2png.py <nethack root> <output textures dir> <output lua>
"""
import os
import re
import sys

from PIL import Image

BACKGROUND = (71, 108, 108)  # tile background colour -> transparent
BLACK = (0, 0, 0)


def remove_drop_shadow(rows, palette):
    """NetHack's tiles draw a drop shadow in black to the lower right of
    each figure. Black pixels are grouped into connected regions; a region
    is shadow when most of its pixels have no coloured (non-black,
    non-background) pixel to their right. Black that belongs to the art
    (outlines, eyes, black creatures) has colour beside it and stays."""
    h, w = len(rows), len(rows[0])

    def kind(x, y):
        rgb = palette[rows[y][x]]
        if rgb == BACKGROUND:
            return "bg"
        return "black" if rgb == BLACK else "color"

    def colour_right(x, y):
        return any(kind(xx, y) == "color" for xx in range(x + 1, w))

    out = [list(r) for r in rows]
    bg_char = next(k for k, v in palette.items() if v == BACKGROUND)
    figure = sum(1 for yy in range(h) for xx in range(w) if kind(xx, yy) != "bg")
    seen = set()
    for y in range(h):
        for x in range(w):
            if (x, y) in seen or kind(x, y) != "black":
                continue
            comp, stack = [], [(x, y)]
            seen.add((x, y))
            while stack:
                cx, cy = stack.pop()
                comp.append((cx, cy))
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in seen                             and kind(nx, ny) == "black":
                        seen.add((nx, ny))
                        stack.append((nx, ny))
            open_right = sum(1 for cx, cy in comp if not colour_right(cx, cy))
            # a black region that is most of the sprite is the creature
            # itself (black monsters), not its shadow
            if len(comp) > 0.5 * figure and len(comp) > 12:
                continue
            if open_right >= 0.7 * len(comp):
                for cx, cy in comp:
                    out[cy][cx] = bg_char
    return ["".join(r) for r in out]


def parse_tile_file(path):
    palette = {}
    tiles = []
    name = None
    rows = None
    with open(path, encoding="latin-1") as f:
        for line in f:
            line = line.rstrip("\n")
            m = re.match(r"^(\S) = \((\d+),\s*(\d+),\s*(\d+)\)", line)
            if m and rows is None:
                palette[m.group(1)] = tuple(int(m.group(i)) for i in (2, 3, 4))
                continue
            m = re.match(r"^# tile (\d+) \((.*)\)", line)
            if m:
                name = m.group(2)
                continue
            if line.strip() == "{":
                rows = []
                continue
            if line.strip() == "}":
                tiles.append((name, rows))
                rows = None
                continue
            if rows is not None:
                rows.append(line.strip())
    return palette, tiles


def tile_image(palette, rows):
    h = len(rows)
    w = len(rows[0])
    img = Image.new("RGBA", (w, h))
    px = img.load()
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            rgb = palette[ch]
            px[x, y] = (0, 0, 0, 0) if rgb == BACKGROUND else rgb + (255,)
    return img


TERRAIN_WORDS = ("wall", "door", "floor", "corridor", "stone", "dark part",
                 "ice", "lava", "pool", "water", "air", "cloud", "drawbridge",
                 "bars", "stair", "ladder", "zap", "beam", "swallow",
                 "explosion", "boom", "shield", "valid position", "poison cloud")


def is_terrain(name):
    return any(w in name for w in TERRAIN_WORDS)


def statue_of(img):
    out = img.copy()
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, a = px[x, y]
            if a:
                v = int(0.3 * r + 0.59 * g + 0.11 * b)
                v = 96 + v * 120 // 255  # stone grey range
                px[x, y] = (v, v, v, 255)
    return out


def main():
    root, outdir, outlua = sys.argv[1:4]
    os.makedirs(outdir, exist_ok=True)
    share = os.path.join(root, "win", "share")
    names = []
    images = []
    nmon = 0
    for fname in ("monsters.txt", "objects.txt", "other.txt"):
        palette, tiles = parse_tile_file(os.path.join(share, fname))
        for name, rows in tiles:
            names.append(name)
            # sprites lose their drop shadow; terrain tiles (used as node
            # textures) keep theirs
            if fname != "other.txt" or not is_terrain(name):
                rows = remove_drop_shadow(rows, palette)
            images.append(tile_image(palette, rows))
        if fname == "monsters.txt":
            nmon = len(tiles)
    for i in range(nmon):
        names.append("statue of " + names[i])
        images.append(statue_of(images[i]))

    for i, img in enumerate(images):
        img.save(os.path.join(outdir, "nhv_tile_%04d.png" % i), optimize=True)

    with open(outlua, "w", encoding="utf-8") as f:
        f.write("-- generated by tools/tiles2png.py; do not edit\n")
        f.write("return {\n  count = %d,\n  monsters = %d,\n  names = {\n" % (len(images), nmon))
        for i, n in enumerate(names):
            f.write("    [%d] = %s,\n" % (i, '"' + n.replace("\\", "\\\\").replace('"', '\\"') + '"'))
        f.write("  },\n}\n")
    print("wrote %d tiles" % len(images))


if __name__ == "__main__":
    main()
