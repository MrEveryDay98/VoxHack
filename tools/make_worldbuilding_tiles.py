"""The world-building sprite sheet: block textures in the vanilla NetHack
tile style (16x16, NetHack's tile palette only - win/share/other.txt -,
flat colours, dark outlines, simple patterns; the field tiles wrap).

The sheet is the working file: mods/nhv_tiles/textures/nhv_worldbuilding.png,
16 sprites a row, growing downwards; mods/nhv_tiles/worldbuilding.json
names each sprite in order. Draw new sprites straight into the sheet (the
next free 16x16 cell) and add their names to the list. Blocks use them as
{"wb": <number>} (the block editor's World-building tab).

    python -I tools/make_worldbuilding_tiles.py --preview   the sheet, 4x,
        each sprite tiled 2x2 and labelled -> build/worldbuilding_preview.png
    python -I tools/make_worldbuilding_tiles.py --init      draw the first
        24 sprites (only when there's no sheet yet: never overwrites it)
"""
import os
import random
from PIL import Image, ImageDraw, ImageFont

import json
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TILES = os.path.join(ROOT, "game", "nethackvoxel", "mods", "nhv_tiles")
SHEET = os.path.join(TILES, "textures", "nhv_worldbuilding.png")
NAMES = os.path.join(TILES, "worldbuilding.json")
FONT = os.path.join(ROOT, "game", "nethackvoxel", "mods", "nhv", "fonts", "nhv_retro.ttf")
COLS = 16

# the vanilla tiles' palette (other.txt letters)
C = {
    "floor": (71, 108, 108),   # .
    "black": (0, 0, 0),        # A
    "cyan": (0, 182, 255),     # B
    "orange": (255, 108, 0),   # C
    "red": (255, 0, 0),        # D
    "blue": (0, 0, 255),       # E
    "green": (0, 145, 0),      # F
    "lime": (108, 255, 0),     # G
    "yellow": (255, 255, 0),   # H
    "magenta": (255, 0, 255),  # I
    "brown": (145, 71, 0),     # J
    "rust": (204, 79, 0),      # K
    "peach": (255, 182, 145),  # L
    "white2": (237, 237, 237), # M
    "white": (255, 255, 255),  # N
    "silver": (215, 215, 215), # O
    "stone": (108, 145, 182),  # P
    "g18": (18, 18, 18),       # Q
    "g54": (54, 54, 54),       # R
    "g73": (73, 73, 73),       # S
    "g82": (82, 82, 82),       # T
    "g104": (104, 104, 104),   # V
    "g131": (131, 131, 131),   # W
    "g149": (149, 149, 149),   # Y
    "g195": (195, 195, 195),   # Z
}
N = 16


def tile(fill):
    im = Image.new("RGBA", (N, N), C[fill] + (255,))
    return im, im.load()


def px(p, x, y, col):
    p[x % N, y % N] = C[col] + (255,)


def rect(p, x0, y0, x1, y1, col):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            px(p, x, y, col)


def speckle(p, rng, cols, n):
    for _ in range(n):
        px(p, rng.randrange(N), rng.randrange(N), rng.choice(cols))


def bricks(face, light, mortar, shade=None, h=4, w=8):
    """running bond: rows of h (mortar on the last), bricks w wide, every
    other row shifted half a brick; a light top-left edge, a shadow edge"""
    im, p = tile(face)
    for row in range(N // h):
        y0 = row * h
        off = (w // 2) * (row % 2)
        for x in range(N):
            px(p, x, y0 + h - 1, mortar)
        for b in range(N // w + 1):
            x0 = b * w + off
            for y in range(y0, y0 + h - 1):
                px(p, x0 + w - 1, y, mortar)
            for x in range(x0, x0 + w - 1):
                px(p, x, y0, light)
            if shade:
                for x in range(x0 + 1, x0 + w - 1):
                    px(p, x, y0 + h - 2, shade)
    return im


def planks(horizontal, rng):
    """boards 4 wide: a dark seam, a light top edge, a few grain streaks,
    each board's end (staggered) with a nail either side"""
    im, p = tile("rust")

    def put(u, v, col):  # (u along the boards, v across them)
        px(p, u, v, col) if horizontal else px(p, v, u, col)

    for k in range(N // 4):
        v0 = k * 4
        end = (k * 6 + 3) % N
        for u in range(N):
            put(u, v0 + 3, "brown")
            put(u, v0, "orange")
        for v in range(v0, v0 + 3):
            put(end, v, "brown")
        put(end - 1, v0 + 1, "black")
        put(end + 1, v0 + 1, "black")
        for _ in range(2):
            u0 = rng.randrange(N)
            for t in range(rng.randrange(3, 6)):
                if (u0 + t) % N not in ((end - 1) % N, end, (end + 1) % N):
                    put(u0 + t, v0 + 2 - (t % 2), "brown")
    return im


def make(rng):
    t = {}

    # 1 dungeon stone bricks (the vanilla wall's blue-grey)
    t["stone_bricks"] = bricks("stone", "silver", "floor", shade="floor")

    # 2 red clay bricks
    t["clay_bricks"] = bricks("rust", "orange", "silver", shade="brown")

    # 3 dark dungeon bricks
    t["dark_bricks"] = bricks("g73", "g104", "g18", shade="g54")

    # 4 cobblestone: rounded grey stones, dark gaps
    im, p = tile("g54")
    stones = [(1, 1, 5, 4), (8, 0, 13, 3), (0, 6, 3, 10), (5, 6, 10, 9), (12, 5, 15, 9),
              (1, 12, 6, 15), (8, 11, 13, 14)]
    for x0, y0, x1, y1 in stones:
        rect(p, x0, y0, x1, y1, "g131")
        for x in range(x0, x1 + 1):
            px(p, x, y0, "g195")
        for y in range(y0, y1 + 1):
            px(p, x0, y, "g149")
        for x in range(x0 + 1, x1 + 1):
            px(p, x, y1, "g104")
        for c in ((x0, y0), (x1, y0), (x0, y1), (x1, y1)):
            px(p, *c, "g54")
    t["cobblestone"] = im

    # 5 flagstones: big pale slabs
    im, p = tile("g149")
    for x in range(N):
        px(p, x, 7, "g82")
        px(p, x, 15, "g82")
    for y in range(0, 7):
        px(p, 9, y, "g82")
    for y in range(8, 15):
        px(p, 3, y, "g82")
    speckle(p, rng, ["g131", "g195"], 22)
    t["flagstone"] = im

    # 6 rough cave rock (the vanilla stone's dither)
    im, p = tile("g82")
    speckle(p, rng, ["g54", "g104", "g54"], 70)
    speckle(p, rng, ["g131"], 10)
    t["cave_rock"] = im

    # 7 mossy stone bricks
    im = bricks("stone", "silver", "floor", shade="floor")
    p = im.load()
    for x, y in [(2, 3), (3, 3), (4, 2), (10, 7), (11, 7), (12, 6), (0, 11), (1, 11), (6, 15), (7, 15),
                 (8, 14), (14, 11), (15, 10), (5, 7), (13, 3)]:
        px(p, x, y, "green")
    for x, y in [(3, 2), (11, 6), (1, 10), (7, 14), (14, 10)]:
        px(p, x, y, "lime")
    t["mossy_bricks"] = im

    # 8 marble tiles
    im, p = tile("white2")
    for x in range(N):
        px(p, x, 7, "g195")
        px(p, x, 15, "g195")
    for y in range(N):
        px(p, 7, y, "g195")
        px(p, 15, y, "g195")
    for x, y in [(1, 2), (2, 3), (3, 3), (4, 4), (9, 10), (10, 10), (11, 11), (12, 12), (2, 12), (3, 11)]:
        px(p, x, y, "silver")
    t["marble"] = im

    # 9 black and white checker floor
    im, p = tile("white2")
    for y in range(N):
        for x in range(N):
            if (x // 4 + y // 4) % 2:
                px(p, x, y, "g18")
    t["checker"] = im

    # 10 horizontal wood planks
    t["planks"] = planks(True, rng)

    # 11 vertical wood planks
    t["planks_vertical"] = planks(False, rng)

    # 12 log end (rings)
    im, p = tile("rust")
    for y in range(N):
        for x in range(N):
            d = ((x - 7.5) ** 2 + (y - 7.5) ** 2) ** 0.5
            if d > 7.6:
                px(p, x, y, "brown")
            elif int(d) % 3 == 1:
                px(p, x, y, "brown")
            elif d < 1.2:
                px(p, x, y, "brown")
    for x, y in [(7, 3), (8, 4), (8, 5)]:
        px(p, x, y, "black")
    t["log_end"] = im

    # 13 dirt
    im, p = tile("brown")
    speckle(p, rng, ["rust", "rust", "g54"], 45)
    speckle(p, rng, ["black"], 8)
    t["dirt"] = im

    # 14 grass
    im, p = tile("green")
    for _ in range(26):
        x, y = rng.randrange(N), rng.randrange(N)
        px(p, x, y, "lime")
        px(p, x, y + 1, "lime")
    speckle(p, rng, ["brown"], 6)
    t["grass"] = im

    # 15 sand
    im, p = tile("peach")
    speckle(p, rng, ["silver", "orange"], 26)
    for x in range(N):
        if x % 5 != 2:
            px(p, x, 4 + (x // 4) % 2, "silver")
            px(p, x, 12 + (x // 4) % 2, "silver")
    t["sand"] = im

    # 16 gravel
    im, p = tile("g104")
    for _ in range(30):
        x, y = rng.randrange(N), rng.randrange(N)
        px(p, x, y, "g149")
        px(p, x + 1, y, "g131")
        px(p, x, y + 1, "g54")
    t["gravel"] = im

    # 17 leaves
    im, p = tile("green")
    for _ in range(14):
        x, y = rng.randrange(N), rng.randrange(N)
        px(p, x, y, "lime")
        px(p, x + 1, y, "lime")
        px(p, x, y + 1, "lime")
        px(p, x + 1, y + 1, "black")
    t["leaves"] = im

    # 18 roof shingles: overlapping rows, scalloped
    im, p = tile("red")
    for row in range(4):
        y0 = row * 4
        off = 2 * (row % 2)
        for x in range(N):
            px(p, x, y0 + 3, "brown")
        for b in range(4):
            x0 = b * 4 + off
            px(p, x0, y0 + 2, "brown")
            px(p, x0 + 3, y0 + 2, "brown")
            px(p, x0 + 1, y0, "orange")
            px(p, x0 + 2, y0, "orange")
    t["roof_shingles"] = im

    # 19 thatch
    im, p = tile("rust")
    for x in range(N):
        for y in range(N):
            if (x * 3 + y) % 5 == 0:
                px(p, x, y, "yellow")
            elif (x * 3 + y) % 5 == 2:
                px(p, x, y, "brown")
    for x in range(N):
        px(p, x, 7, "brown")
        px(p, x, 15, "brown")
    t["thatch"] = im

    # 20 iron plate, riveted
    im, p = tile("g131")
    for x in range(N):
        px(p, x, 0, "g195")
        px(p, x, 15, "g54")
    for y in range(N):
        px(p, 0, y, "g195")
        px(p, 15, y, "g54")
    for x, y in [(2, 2), (13, 2), (2, 13), (13, 13)]:
        px(p, x, y, "white2")
        px(p, x + 1, y + 1, "g18")
    for x in range(3, 13):
        px(p, x, 7, "g104")
        px(p, x, 8, "g149")
    t["iron_plate"] = im

    # 21 gold tiles (a treasury's floor)
    im, p = tile("yellow")
    for x in range(N):
        px(p, x, 7, "rust")
        px(p, x, 15, "rust")
    for y in range(N):
        px(p, 7, y, "rust")
        px(p, 15, y, "rust")
    for x, y in [(1, 1), (2, 1), (1, 2), (9, 9), (10, 9), (9, 10)]:
        px(p, x, y, "white")
    for x, y in [(5, 5), (6, 6), (13, 13), (14, 14)]:
        px(p, x, y, "orange")
    t["gold_tiles"] = im

    # 22 red carpet with a gold border pattern (wraps as a field)
    im, p = tile("red")
    for x in range(N):
        if x % 4 in (1, 2):
            px(p, x, 0, "yellow")
            px(p, x, 8, "yellow")
    for x, y in [(3, 4), (4, 3), (5, 4), (4, 5), (11, 12), (12, 11), (13, 12), (12, 13)]:
        px(p, x, y, "yellow")
    px(p, 4, 4, "blue")
    px(p, 12, 12, "blue")
    t["carpet"] = im

    # 23 ice
    im, p = tile("cyan")
    for i in range(N):
        px(p, i, (i * 2) % N, "white")
        px(p, i, (i * 2 + 1) % N, "white2")
    speckle(p, rng, ["white"], 10)
    for x, y in [(3, 9), (4, 10), (5, 10), (11, 3), (12, 4)]:
        px(p, x, y, "blue")
    t["ice"] = im

    # 24 bookshelf (a block face, not a wrapping field)
    im, p = tile("brown")
    for x in range(N):
        px(p, x, 0, "rust")
        px(p, x, 7, "rust")
        px(p, x, 8, "rust")
        px(p, x, 15, "rust")
    books = ["red", "blue", "green", "yellow", "magenta", "cyan", "rust", "silver"]
    for shelf in (1, 9):
        x = 1
        while x < 15:
            col = rng.choice(books)
            hgt = rng.randrange(4, 7)
            top = shelf + 6 - hgt
            for y in range(top, shelf + 6):
                px(p, x, y, col)
            px(p, x, top, "white2" if col not in ("silver", "yellow") else "g131")
            x += 1 + (1 if rng.random() < 0.25 else 0)
            if x < 15 and rng.random() < 0.3:
                px(p, x, shelf + 5, "black")
                x += 1
    for y in range(N):
        px(p, 0, y, "rust")
        px(p, 15, y, "black")
    t["bookshelf"] = im

    return t


def init():
    if os.path.exists(SHEET):
        sys.exit("the sheet exists already (it's the working file): not overwritten")
    rng = random.Random(1987)  # (NetHack's first year)
    tiles = make(rng)
    names = list(tiles)
    rows = (len(names) + COLS - 1) // COLS
    sheet = Image.new("RGBA", (COLS * N, rows * N), (0, 0, 0, 0))
    for i, name in enumerate(names):
        sheet.paste(tiles[name], ((i % COLS) * N, (i // COLS) * N))
    sheet.save(SHEET)
    with open(NAMES, "w", encoding="utf-8") as f:
        json.dump({"cols": COLS, "names": names}, f, indent=1)
    print(len(names), "sprites ->", SHEET)


def preview():
    sheet = Image.open(SHEET).convert("RGBA")
    names = json.load(open(NAMES, encoding="utf-8"))["names"]
    cols = sheet.width // N
    n = (sheet.width // N) * (sheet.height // N)
    S, gap, lab, per_row = 4, 10, 30, 6
    cw = ch = 2 * N * S
    shown = [i for i in range(n) if sheet.crop(((i % cols) * N, (i // cols) * N,
                                                (i % cols) * N + N, (i // cols) * N + N)).getbbox()]
    rows = (len(shown) + per_row - 1) // per_row
    prev = Image.new("RGB", (per_row * (cw + gap) + gap, rows * (ch + lab + gap) + gap), (24, 24, 30))
    d = ImageDraw.Draw(prev)
    f = ImageFont.truetype(FONT, 14)
    for k, i in enumerate(shown):
        x0 = gap + (k % per_row) * (cw + gap)
        y0 = gap + (k // per_row) * (ch + lab + gap)
        cell = sheet.crop(((i % cols) * N, (i // cols) * N, (i % cols) * N + N, (i // cols) * N + N))
        big = cell.resize((N * S, N * S), Image.NEAREST)
        for dx in (0, 1):
            for dy in (0, 1):
                prev.paste(big, (x0 + dx * N * S, y0 + dy * N * S), big)
        name = names[i] if i < len(names) and names[i] else "(unnamed)"
        d.text((x0, y0 + ch + 6), "%d %s" % (i, name), font=f, fill=(230, 230, 220))
    out = os.path.join(ROOT, "build", "worldbuilding_preview.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    prev.save(out)
    print(out)


if __name__ == "__main__":
    if "--init" in sys.argv:
        init()
    if "--preview" in sys.argv or len(sys.argv) == 1:
        preview()
