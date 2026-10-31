"""VoxHack's icon, from the game's ICON.png (32x32, drawn by hand), for the
engine: its window's icon (textures/base/pack/nhv_icon.png, 128x128) and
the program's own (misc/voxhack-icon.ico: 16 to 256 pixels, built into
luanti.exe - Explorer, the taskbar, the Play shortcut). Bigger sizes are its
pixels made bigger, sharp; the small ones averaged down.

Usage: python -I tools/make_icon.py   (tools/deploy.sh runs it)
"""
import io
import os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "game", "nethackvoxel", "mods", "nhv_tiles", "textures", "ICON.png")
LUANTI = os.path.join(ROOT, "external", "luanti")
WINDOW = os.path.join(LUANTI, "textures", "base", "pack", "nhv_icon.png")
ICO = os.path.join(LUANTI, "misc", "voxhack-icon.ico")
ICO_SIZES = [16, 24, 32, 48, 64, 128, 256]


def sized(im, n):
    w = im.size[0]
    if n >= w:
        return im.resize((n, n), Image.NEAREST)
    return im.resize((n, n), Image.BOX)


def write_if_changed(path, data):
    old = open(path, "rb").read() if os.path.exists(path) else None
    if old != data:
        open(path, "wb").write(data)
        return True
    return False


def main():
    im = Image.open(SRC).convert("RGBA")
    if im.size[0] != im.size[1]:
        raise SystemExit("ICON.png isn't square")
    out = io.BytesIO()
    sized(im, 128).save(out, format="PNG")
    write_if_changed(WINDOW, out.getvalue())
    out = io.BytesIO()
    # (each size of its own: Pillow's own resizing of the biggest would blur them)
    sized(im, 256).save(out, format="ICO", sizes=[(n, n) for n in ICO_SIZES],
                        append_images=[sized(im, n) for n in ICO_SIZES if n != 256])
    if write_if_changed(ICO, out.getvalue()):
        # (the build doesn't see the icon change, only the script naming it)
        os.utime(os.path.join(LUANTI, "misc", "winresource.rc"))
        print("icon: made anew")


if __name__ == "__main__":
    main()
