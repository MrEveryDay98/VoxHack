"""Draw the built-in particle pictures for the Effects tab.

    python tools/make_fx_textures.py

Writes game/nethackvoxel/mods/nhv_effects/textures/nhvfx_{dot,spark,star,
square,ring}.png: small white shapes (the effect's colour tints them),
drawn with hard pixels to match the game.
"""
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "game", "nethackvoxel", "mods", "nhv_effects", "textures")


def draw(rows):
    """rows of characters: '#' white, '+' half-transparent white, other clear"""
    h, w = len(rows), len(rows[0])
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for y, row in enumerate(rows):
        for x, c in enumerate(row):
            if c == "#":
                im.putpixel((x, y), (255, 255, 255, 255))
            elif c == "+":
                im.putpixel((x, y), (255, 255, 255, 128))
    return im


SHAPES = {
    "dot": [
        "..++..",
        ".+##+.",
        "+####+",
        "+####+",
        ".+##+.",
        "..++..",
    ],
    "spark": [
        "...#...",
        "...#...",
        "..+#+..",
        "###.###",
        "..+#+..",
        "...#...",
        "...#...",
    ],
    "star": [
        "....#....",
        "....#....",
        "...###...",
        "#########",
        ".#######.",
        "..#####..",
        "..##.##..",
        ".##...##.",
        ".#.....#.",
    ],
    "square": [
        "####",
        "####",
        "####",
        "####",
    ],
    "ring": [
        "..####..",
        ".#....#.",
        "#......#",
        "#......#",
        "#......#",
        "#......#",
        ".#....#.",
        "..####..",
    ],
}


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, rows in SHAPES.items():
        draw(rows).save(os.path.join(OUT, "nhvfx_%s.png" % name))
        print("nhvfx_%s.png" % name)


if __name__ == "__main__":
    main()
