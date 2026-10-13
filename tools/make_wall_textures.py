"""Make seamless 16x16 wall textures from NetHack's wall sprites.

NetHack's wall sprites are drawn for a top-down map: the brick ones have a
lit top edge and the mines' rock ones have black bands, so they show seams
when repeated over a 3D wall. This builds textures that tile in both
directions from the repeating part of each sprite:

  bricks (main dungeon, Gehennom, Sokoban): the two offset brick courses
      at the bottom, made 3 px tall (+1 px mortar) so 4 courses fill 16 px
  mines (cave): the band of rock lumps with the black gaps filled, stacked
      twice with the second copy shifted half a tile
  knox: its repeating lower band, doubled

Writes nhv_wall_<style>.png next to the sprite sheet. Existing files are
kept (they're yours to edit) unless --force is given.

usage: python make_wall_textures.py <textures dir> [--force]
"""
import os
import sys

COLS = 48
# sheet position of each set's "horizontal wall" sprite
SPRITES = {"main": 917, "mines": 1115, "gehennom": 1126, "knox": 1137, "sokoban": 1148}


def sprite(sheet, index):
    x, y = (index % COLS) * 16, (index // COLS) * 16
    return sheet.crop((x, y, x + 16, y + 16))


def rows(img, r0, r1):
    return [[img.getpixel((x, y)) for x in range(16)] for y in range(r0, r1)]


def build(grid):
    from PIL import Image
    out = Image.new("RGBA", (16, len(grid)))
    for y, row in enumerate(grid):
        for x, p in enumerate(row):
            out.putpixel((x, y), p)
    return out


def bricks(src):
    # rows 8..14: mortar, course A (2 rows), mortar, course B (2 rows), mortar
    mortar = rows(src, 8, 9)[0]
    a_top, a_bot = rows(src, 9, 11)
    b_top, b_bot = rows(src, 12, 14)
    course_a = [mortar, a_top, a_bot, a_bot]
    course_b = [mortar, b_top, b_bot, b_bot]
    return build(course_a + course_b + course_a + course_b)


def cave(src):
    band = rows(src, 2, 10)
    fill = src.getpixel((0, 12))  # the rock's dark body colour
    band = [[fill if p[:3] == (0, 0, 0) else p for p in row] for row in band]
    shifted = [row[8:] + row[:8] for row in band]
    return build(band + shifted)


def knox(src):
    band = rows(src, 7, 15)
    return build(band + band)


def main():
    out_dir = sys.argv[1]
    force = "--force" in sys.argv
    todo = [s for s in SPRITES
            if force or not os.path.exists(os.path.join(out_dir, "nhv_wall_%s.png" % s))]
    if not todo:
        return
    from PIL import Image  # only needed when there's something to make
    sheet = Image.open(os.path.join(out_dir, "nhv_tiles.png")).convert("RGBA")
    makers = {"main": bricks, "gehennom": bricks, "sokoban": bricks, "mines": cave, "knox": knox}
    for style in todo:
        index = SPRITES[style]
        path = os.path.join(out_dir, "nhv_wall_%s.png" % style)
        makers[style](sprite(sheet, index)).save(path)
        print("wrote", path)


if __name__ == "__main__":
    main()
