"""Make nhv_tiles_noshadow.png: the tile sheet without the shadows drawn on
the sprites (an alternate look, for the game's real shadows: shadows.lua).

NetHack's tiles draw a shadow in black to the lower right of each sprite
and under it (in blue-grey for black things: those more than half black
lose that instead). This takes away the black that reaches the outside of
the sprite (from the transparent background, through black only), keeping:
  - black enclosed by colour (eyes, mouths, markings),
  - black lines running between colour on opposite sides (a stripe
    between two parts),
and where taking a pixel away would split the sprite into pieces, it's
painted in a neighbouring colour instead, joining them.

Hand corrections, per sheet position, are in tools/noshadow_overrides.json:
  "skip":  sprites left as they are
  "force": mostly black sprites done as the rest are (their black being
           mostly shadow: an amulet's, a knife's)
  "right": figures dressed in black: only black right of the body goes
  "shade": sprites with a blue-grey shadow though less than half black
  "manual": nothing taken but the "clear" pixels
  "hanging": creatures hanging from the ceiling (their shadow is at their top)
  "keep":  {pos: [[x, y], ...]} black pixels to keep
  "clear": {pos: [[x, y], ...]} pixels to take away anyway
  "paint": {pos: [[x, y, "#rrggbb"], ...]} pixels to set

Run again after editing nhv_tiles.png:
    python -I tools/make_noshadow_tiles.py [--sheets OUTDIR]
(--sheets writes before/after contact sheets for checking.)
"""
import json
import os
import sys
from collections import Counter

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEX = os.path.join(ROOT, "game", "nethackvoxel", "mods", "nhv_tiles", "textures")
SRC = os.path.join(TEX, "nhv_tiles.png")
DST = os.path.join(TEX, "nhv_tiles_noshadow.png")
OVERRIDES = os.path.join(ROOT, "tools", "noshadow_overrides.json")

PX, COLS = 16, 48
# sheet positions of sprites with drawn shadows: monsters and objects (the
# map's own pictures, zaps and explosions after them have none)
SPRITES = range(0, 915)
# sprites more black than this are mostly black creatures and things (a
# black cat): the tiles draw their shadow in blue-grey (SHADE) instead,
# so that's what goes from them (and a flyer's separate patch beneath)
DARK = 0.5
SHADE = (108, 145, 182)
# monsters (sprites before this are creatures) keep black in the top HEAD
# of their height
CREATURES = 431
HEAD = 0.3
BLACK = (0, 0, 0)
N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
N8 = N4 + ((1, 1), (1, -1), (-1, 1), (-1, -1))


def is_black(p):
    return p[3] > 0 and p[:3] == BLACK


def is_color(p):
    return p[3] > 0 and p[:3] != BLACK


def components(px, member):
    """8-connected groups of pixels for which member(p) is true"""
    seen, groups = set(), []
    for y in range(PX):
        for x in range(PX):
            if (x, y) in seen or not member(px[y][x]):
                continue
            stack, group = [(x, y)], []
            seen.add((x, y))
            while stack:
                cx, cy = stack.pop()
                group.append((cx, cy))
                for dx, dy in N8:
                    nx, ny = cx + dx, cy + dy
                    if 0 <= nx < PX and 0 <= ny < PX and (nx, ny) not in seen and member(px[ny][nx]):
                        seen.add((nx, ny))
                        stack.append((nx, ny))
            groups.append(group)
    return groups


def remove_shadow(px, creature=False):
    """px: 16 rows of 16 RGBA tuples, changed in place. A creature's
    shadow lies beside and below it, never over its top (HEAD of its
    height: black hair, hats), so black there stays"""
    def at(x, y):
        return px[y][x] if 0 <= x < PX and 0 <= y < PX else (0, 0, 0, 0)

    # black reachable from outside through black only
    outer = set()
    stack = []
    for y in range(PX):
        for x in range(PX):
            if is_black(px[y][x]) and any(at(x + dx, y + dy)[3] == 0 for dx, dy in N4):
                outer.add((x, y))
                stack.append((x, y))
    while stack:
        x, y = stack.pop()
        for dx, dy in N4:
            n = (x + dx, y + dy)
            if n not in outer and 0 <= n[0] < PX and 0 <= n[1] < PX and is_black(px[n[1]][n[0]]):
                outer.add(n)
                stack.append(n)
    # ... but not lines between colour on opposite sides
    drop = {(x, y) for x, y in outer
            if not ((is_color(at(x - 1, y)) and is_color(at(x + 1, y)))
                    or (is_color(at(x, y - 1)) and is_color(at(x, y + 1))))}
    if creature:
        ys = [y for y in range(PX) for x in range(PX) if is_color(px[y][x])]
        if ys:
            head = min(ys) + (max(ys) - min(ys)) * HEAD

            def over_head(x, y):
                # (in a row with no colour - a hat's crown - or by the
                # row's colour: not the shadow's top, further out)
                xs = [cx for cx in range(PX) if is_color(px[y][cx])]
                return not xs or min(xs) - 1 <= x <= max(xs) + 1
            drop = {(x, y) for x, y in drop if y >= head or not over_head(x, y)}
    # (the sprite's pieces with some colour in them: a flyer's separate
    # shadow below it isn't one)
    pieces_before = sum(1 for g in components(px, lambda p: p[3] > 0)
                        if any(is_color(px[y][x]) for x, y in g))
    for x, y in drop:
        px[y][x] = (0, 0, 0, 0)
    # joins: a taken pixel between pieces of colour gets a neighbour's colour,
    # while that makes fewer pieces, until the sprite is in as few pieces as
    # it was (black and all)
    def pieces():
        return len(components(px, lambda p: p[3] > 0))
    target = max(1, pieces_before)
    changed = True
    while pieces() > target and changed:
        changed = False
        before = pieces()
        for x, y in sorted(drop):
            if px[y][x][3] != 0:
                continue
            near = [at(x + dx, y + dy) for dx, dy in N8 if is_color(at(x + dx, y + dy))]
            if len(near) < 2:
                continue
            px[y][x] = Counter(near).most_common(1)[0][0]
            if pieces() < before:
                changed = True
                break
            px[y][x] = (0, 0, 0, 0)
    return len(drop)


def outer(px, member):
    """pixels for which member(p) is true, reachable from the outside
    (the transparent background) through such pixels only"""
    def at(x, y):
        return px[y][x] if 0 <= x < PX and 0 <= y < PX else (0, 0, 0, 0)
    found, stack = set(), []
    for y in range(PX):
        for x in range(PX):
            if member(px[y][x]) and any(at(x + dx, y + dy)[3] == 0 for dx, dy in N4):
                found.add((x, y))
                stack.append((x, y))
    while stack:
        x, y = stack.pop()
        for dx, dy in N4:
            n = (x + dx, y + dy)
            if n not in found and 0 <= n[0] < PX and 0 <= n[1] < PX and member(px[n[1]][n[0]]):
                found.add(n)
                stack.append(n)
    return found


def remove_dark_shadow(px):
    """a mostly black sprite: its blue-grey shadow, and black patches
    with no colour in them wholly below it (a flyer's)"""
    for x, y in outer(px, lambda p: p[3] > 0 and p[:3] == SHADE):
        px[y][x] = (0, 0, 0, 0)
    groups = components(px, lambda p: p[3] > 0)
    if len(groups) > 1:
        main = max(groups, key=len)
        bottom = max(y for _, y in main)
        for g in groups:
            if g is not main and all(is_black(px[y][x]) for x, y in g) and min(y for _, y in g) > bottom:
                for x, y in g:
                    px[y][x] = (0, 0, 0, 0)


def remove_right(px):
    """a figure dressed in black: only the black right of its body in
    each row (right of the row's last coloured pixel) goes"""
    edge = outer(px, is_black)
    for y in range(PX):
        xs = [x for x in range(PX) if is_color(px[y][x])]
        if xs:
            for x in range(max(xs) + 1, PX):
                if (x, y) in edge:
                    px[y][x] = (0, 0, 0, 0)


def load_overrides():
    if not os.path.exists(OVERRIDES):
        return {"skip": set(), "force": set(), "keep": {}, "clear": {}, "paint": {}}
    with open(OVERRIDES, encoding="utf-8") as f:
        o = json.load(f)
    for k in ("keep", "clear", "paint"):
        o[k] = {int(p): v for p, v in o.get(k, {}).items()}
    o["skip"] = set(o.get("skip", []))
    o["force"] = set(o.get("force", []))
    o["right"] = set(o.get("right", []))
    o["shade"] = set(o.get("shade", []))
    o["manual"] = set(o.get("manual", []))
    o["hanging"] = set(o.get("hanging", []))
    return o


def hex_rgba(h):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 255)


def tile_px(im, pos):
    ox, oy = (pos % COLS) * PX, (pos // COLS) * PX
    return [[im.getpixel((ox + x, oy + y)) for x in range(PX)] for y in range(PX)]


def put_px(im, pos, px):
    ox, oy = (pos % COLS) * PX, (pos // COLS) * PX
    for y in range(PX):
        for x in range(PX):
            im.putpixel((ox + x, oy + y), px[y][x])


def main():
    src = Image.open(SRC).convert("RGBA")
    out = src.copy()
    o = load_overrides()
    dark = []
    for pos in SPRITES:
        if pos in o["skip"]:
            continue
        px = tile_px(src, pos)
        orig = [row[:] for row in px]
        solid = [p for row in px for p in row if p[3] > 0]
        if pos in o["manual"]:
            pass
        elif pos in o["right"]:
            remove_right(px)
        elif pos in o["shade"]:
            remove_dark_shadow(px)
        elif solid and sum(1 for p in solid if is_black(p)) / len(solid) > DARK and pos not in o["force"]:
            dark.append(pos)
            remove_dark_shadow(px)
        else:
            remove_shadow(px, pos < CREATURES and pos not in o["hanging"])
        for x, y in o["keep"].get(pos, []):
            px[y][x] = orig[y][x]
        for x, y in o["clear"].get(pos, []):
            px[y][x] = (0, 0, 0, 0)
        for x, y, c in o["paint"].get(pos, []):
            px[y][x] = hex_rgba(c)
        put_px(out, pos, px)
    out.save(DST)
    print("wrote", DST)
    print("mostly black (blue-grey shadows taken):", dark)
    if "--sheets" in sys.argv:
        contact_sheets(src, out, sys.argv[sys.argv.index("--sheets") + 1])


def contact_sheets(src, out, outdir, per=96, cols=16, z=4):
    """before (top) / after (bottom) pairs, numbered, per sheets of `per`"""
    from PIL import ImageDraw
    os.makedirs(outdir, exist_ok=True)
    cell = PX * z + 6
    for start in range(SPRITES.start, SPRITES.stop, per):
        idx = list(range(start, min(start + per, SPRITES.stop)))
        rows = (len(idx) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * cell, rows * (2 * cell + 12)), (40, 40, 40))
        d = ImageDraw.Draw(sheet)
        for k, pos in enumerate(idx):
            cx, cy = (k % cols) * cell, (k // cols) * (2 * cell + 12)
            for j, im in enumerate((src, out)):
                t = im.crop(((pos % COLS) * PX, (pos // COLS) * PX,
                             (pos % COLS) * PX + PX, (pos // COLS) * PX + PX)).resize((PX * z, PX * z), Image.NEAREST)
                bg = Image.new("RGBA", t.size, (120, 175, 120, 255))
                bg.alpha_composite(t)
                sheet.paste(bg.convert("RGB"), (cx + 3, cy + 12 + j * cell))
            d.text((cx + 3, cy), str(pos), fill=(255, 255, 255))
        sheet.save(os.path.join(outdir, "noshadow_%04d.png" % start))


if __name__ == "__main__":
    main()
