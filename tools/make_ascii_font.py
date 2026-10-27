"""Make ASCII mode's characters (mods/nhv_tiles/textures):
  nhv_ascii.png          the 256 characters of the IBM PC's code page 437,
                         16 x 16 cells of 8 x 14 pixels, white on
                         see-through, in code order (row = code // 16,
                         column = code % 16): plain ASCII for NetHack's own
                         symbols, the rest for the Rogue level's (Epyx Rogue:
                         double-line walls, the smiley you, card suits...)
  nhv_ascii_palette.png  NetHack's 16 colours, 16 x 1, in its colour order
                         (CLR_BLACK = 0 ... CLR_WHITE = 15): the letter
                         blocks' palette (nhv/ascii.lua)

Drawn from the IBM EGA's own 8x14 text font, as VileR's Oldschool PC Font
Resource has it (https://int10h.org/oldschool-pc-fonts/, CC BY-SA 4.0:
nhv_ascii.png is under that licence too - CREDITS.md):
tools/fonts/Px437_IBM_EGA_8x14.ttf, pixel for pixel.

    python tools/make_ascii_font.py
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "game", "nethackvoxel", "mods", "nhv_tiles", "textures")
FONT = os.path.join(HERE, "fonts", "Px437_IBM_EGA_8x14.ttf")

CW, CH = 8, 14  # the EGA's character cell

# code page 437's pictures for codes 0-31 and 127 (Python's cp437 codec
# gives control characters there)
LOW = (" ☺☻♥♦♣♠•◘○◙♂♀♪♫☼"
       "►◄↕‼¶§▬↨↑↓→←∟↔▲▼")

# NetHack's colours (CLR_BLACK ... CLR_WHITE) as the EGA showed them; black
# is the EGA's dark grey, so black things (and remembered dark floor) show
PALETTE = [
    (0x55, 0x55, 0x55), (0xAA, 0x00, 0x00), (0x00, 0xAA, 0x00), (0xAA, 0x55, 0x00),
    (0x00, 0x00, 0xAA), (0xAA, 0x00, 0xAA), (0x00, 0xAA, 0xAA), (0xAA, 0xAA, 0xAA),
    (0xAA, 0xAA, 0xAA), (0xFF, 0x55, 0x55), (0x55, 0xFF, 0x55), (0xFF, 0xFF, 0x55),
    (0x55, 0x55, 0xFF), (0xFF, 0x55, 0xFF), (0x55, 0xFF, 0xFF), (0xFF, 0xFF, 0xFF),
]


def char_of(code):
    if code < 32:
        return LOW[code]
    if code == 127:
        return "⌂"
    return bytes([code]).decode("cp437")


def pixel_font():
    """The font at the size where one of its pixels is one pixel (its full
    block, code 219, exactly a cell), and where a cell's top is."""
    for size in range(8, 40):
        font = ImageFont.truetype(FONT, size)
        box = font.getbbox("█")
        if box[2] - box[0] == CW and box[3] - box[1] == CH:
            return font, box[0], box[1]
    sys.exit("couldn't find the size where %s's cells are %dx%d" % (FONT, CW, CH))


def main():
    if not os.path.exists(FONT):
        sys.exit("needs %s (the Oldschool PC Font Resource's pack, "
                 "https://int10h.org/oldschool-pc-fonts/download/)" % FONT)
    font, x0, y0 = pixel_font()
    sheet = Image.new("RGBA", (CW * 16, CH * 16), (0, 0, 0, 0))
    white = Image.new("RGBA", (CW, CH), (255, 255, 255, 255))
    for code in range(256):
        cell = Image.new("L", (CW, CH), 0)
        ImageDraw.Draw(cell).text((-x0, -y0), char_of(code), font=font, fill=255)
        mask = cell.point(lambda v: 255 if v >= 128 else 0)
        sheet.paste(white, ((code % 16) * CW, (code // 16) * CH), mask)
    sheet.save(os.path.join(OUT, "nhv_ascii.png"))
    pal = Image.new("RGB", (16, 1))
    for i, c in enumerate(PALETTE):
        pal.putpixel((i, 0), c)
    pal.save(os.path.join(OUT, "nhv_ascii_palette.png"))
    print("wrote nhv_ascii.png (%dx%d cells) and nhv_ascii_palette.png" % (CW, CH))


if __name__ == "__main__":
    main()
