"""Make the beam of light for getting an artifact (cutscene.lua):
  textures/nhv_glory_beam.png  its light: brightest at the top, fading to
                               nothing at the floor
  models/nhv_glory_beam.obj    its shape: a round, open-ended cone, a
                               little wider at the floor than at the top
                               (entity mesh units: 10 to a node)

    python tools/make_glory_beam.py
"""
import math
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
MOD = os.path.join(HERE, "..", "game", "nethackvoxel", "mods", "nhv")
COLOR = (255, 244, 200)
SIDES = 32
HEIGHT = 4.5             # nodes: the floor to the ceiling (walls are 4 high)
R_TOP, R_BOTTOM = 0.38, 0.78


def texture():
    w, h = 4, 64
    im = Image.new("RGBA", (w, h))
    px = im.load()
    for y in range(h):
        up = 1 - y / (h - 1)  # 1 at the top row, 0 at the bottom
        a = int(200 * up ** 1.4)
        for x in range(w):
            px[x, y] = COLOR + (a,)
    im.save(os.path.join(MOD, "textures", "nhv_glory_beam.png"))


def model():
    s = 10  # mesh units to a node
    lines = ["# the beam of light (tools/make_glory_beam.py)"]
    for i in range(SIDES + 1):
        a = 2 * math.pi * i / SIDES
        for r, y in ((R_BOTTOM, 0), (R_TOP, HEIGHT)):
            lines.append("v %.4f %.4f %.4f" % (math.cos(a) * r * s, y * s, math.sin(a) * r * s))
    for i in range(SIDES + 1):
        lines.append("vt %.4f 0" % (i / SIDES))  # (the floor: the image's bottom)
        lines.append("vt %.4f 1" % (i / SIDES))  # (the top: the image's top)
    lines.append("vn 0 0 1")
    for i in range(SIDES):
        b0, t0, b1, t1 = 2 * i + 1, 2 * i + 2, 2 * i + 3, 2 * i + 4
        lines.append("f %d/%d/1 %d/%d/1 %d/%d/1 %d/%d/1" % (b0, b0, b1, b1, t1, t1, t0, t0))
    with open(os.path.join(MOD, "models", "nhv_glory_beam.obj"), "w", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def main():
    texture()
    model()
    print("wrote nhv_glory_beam.png and nhv_glory_beam.obj")


if __name__ == "__main__":
    main()
