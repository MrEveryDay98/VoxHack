"""Write game/nethackvoxel/mods/nhv/models/nhv_bubble.obj: a smooth sphere
for the Plane of Water's air bubbles (nhv/bubbles.lua), with normals and
texture coordinates.

Radius 5 units: a mesh's units are tenths of a node, so at visual size 1
it is one node across - bubbles.lua stretches it to each bubble's size.

    python -I tools/make_bubble_mesh.py
"""
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
MODELS = os.path.join(HERE, "..", "game", "nethackvoxel", "mods", "nhv", "models")
OUT = os.path.join(MODELS, "nhv_bubble.obj")

R = 5.0
SEGMENTS = 32  # round the middle
RINGS = 20     # pole to pole


def main():
    v, vt, vn, faces = [], [], [], []
    for i in range(RINGS + 1):
        theta = math.pi * i / RINGS  # from the top pole down
        for j in range(SEGMENTS + 1):
            phi = 2 * math.pi * j / SEGMENTS
            x = math.sin(theta) * math.cos(phi)
            y = math.cos(theta)
            z = math.sin(theta) * math.sin(phi)
            v.append((R * x, R * y, R * z))
            vn.append((x, y, z))
            vt.append((j / SEGMENTS, 1 - i / RINGS))
    row = SEGMENTS + 1
    for i in range(RINGS):
        for j in range(SEGMENTS):
            a = i * row + j + 1
            b = a + row
            faces.append((a, b, b + 1))
            faces.append((a, b + 1, a + 1))
    with open(OUT, "w", newline="\n") as f:
        f.write("# an air bubble of the Plane of Water (tools/make_bubble_mesh.py)\n")
        for p in v:
            f.write("v %.4f %.4f %.4f\n" % p)
        for t in vt:
            f.write("vt %.4f %.4f\n" % t)
        for n in vn:
            f.write("vn %.4f %.4f %.4f\n" % n)
        for a, b, c in faces:
            f.write("f %d/%d/%d %d/%d/%d %d/%d/%d\n" % (a, a, a, b, b, b, c, c, c))
    print("wrote %s (%d vertices, %d triangles)" % (OUT, len(v), len(faces)))


if __name__ == "__main__":
    main()
