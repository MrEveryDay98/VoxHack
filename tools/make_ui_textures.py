"""Draw the "Retro" interface pieces (old PC style bevelled boxes).

    python tools/make_ui_textures.py

Writes game/nethackvoxel/mods/nhv_tiles/textures/nhv_ui_*.png. They're
9-sliced (the borders keep their size, the middle stretches), and drawn
with sharp pixels, so they're tiny.
"""
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "game", "nethackvoxel", "mods", "nhv_tiles", "textures")

# the classic 16-colour PC palette
BLACK = (0, 0, 0, 255)
DGREY = (85, 85, 85, 255)
LGREY = (170, 170, 170, 255)
WHITE = (255, 255, 255, 255)
BLUE = (0, 0, 170, 255)
DARK = (8, 8, 20, 235)


def box(size, fill, light, dark, border=2, outline=None):
    """A bevelled box: light top/left edges, dark bottom/right ones."""
    im = Image.new("RGBA", (size, size), fill)
    px = im.load()
    for i in range(border):
        for t in range(size):
            px[t, i] = light            # top
            px[i, t] = light            # left
            px[t, size - 1 - i] = dark  # bottom
            px[size - 1 - i, t] = dark  # right
    if outline:
        for t in range(size):
            px[t, 0] = px[0, t] = px[t, size - 1] = px[size - 1, t] = outline
    return im


def panel():
    """A window: a grey double frame around a dark middle."""
    s = 16
    im = Image.new("RGBA", (s, s), DARK)
    px = im.load()
    for t in range(s):
        for a, c in ((0, LGREY), (1, DGREY), (3, LGREY)):
            px[t, a] = px[a, t] = px[t, s - 1 - a] = px[s - 1 - a, t] = c
        px[t, 2] = px[2, t] = px[t, s - 3] = px[s - 3, t] = DARK
    # (the double line: grey, gap, grey; corners stay square)
    return im


def vignette(size=128):
    """White, see-through in the middle, solid toward the edges (the HUD
    tints it: red when hurt, green when healed)."""
    im = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    px = im.load()
    c = (size - 1) / 2
    for y in range(size):
        for x in range(size):
            # (an ellipse that touches the edges; corners darkest)
            d = (((x - c) / c) ** 2 + ((y - c) / c) ** 2) ** 0.5
            t = max(0.0, min(1.0, (d - 0.55) / 0.6))
            a = int(255 * t * t * (3 - 2 * t))
            px[x, y] = (255, 255, 255, a)
    return im


def main():
    os.makedirs(OUT, exist_ok=True)
    pieces = {
        "nhv_ui_panel.png": panel(),
        "nhv_ui_button.png": box(8, DGREY, LGREY, BLACK, outline=BLACK),
        "nhv_ui_button_hover.png": box(8, (0, 0, 170, 255), (85, 85, 255, 255), BLACK, outline=BLACK),
        "nhv_ui_button_pressed.png": box(8, (0, 0, 120, 255), BLACK, (85, 85, 255, 255), outline=BLACK),
        "nhv_ui_field.png": box(8, BLACK, DGREY, LGREY, border=1),
        "nhv_ui_slot.png": box(8, (20, 20, 30, 255), BLACK, DGREY, border=1),
        "nhv_vignette.png": vignette(),
    }
    for name, im in pieces.items():
        im.save(os.path.join(OUT, name))
        print(name)


if __name__ == "__main__":
    main()
