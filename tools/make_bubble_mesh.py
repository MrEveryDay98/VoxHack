"""Write the Plane of Water's air bubble meshes (nhv/bubbles.lua):
  models/nhv_bubble.obj       a smooth sphere, with normals and texture
                              coordinates
  models/nhv_bubble_ring.obj  a thin flat ring, where a bubble meets the
                              floor - its edge, to walk up to

Radius 5 units: a mesh's units are tenths of a node, so at visual size 1
it is one node across - bubbles.lua stretches it to each bubble's size.

    python -I tools/make_bubble_mesh.py
"""
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
MODELS = os.path.join(HERE, "..", "game", "nethackvoxel", "mods", "nhv", "models")
OUT = os.path.join(MODELS, "nhv_bubble.obj")
RING_OUT = os.path.join(MODELS, "nhv_bubble_ring.obj")
RING_INNER = 0.96  # (its inside, as a part of its outside radius R)

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
    ring()


def ring():
    v, vt, faces = [], [], []
    for j in range(SEGMENTS + 1):
        phi = 2 * math.pi * j / SEGMENTS
        c, s = math.cos(phi), math.sin(phi)
        v.append((R * c, 0.0, R * s))
        v.append((R * RING_INNER * c, 0.0, R * RING_INNER * s))
        vt.append((j / SEGMENTS, 0.0))
        vt.append((j / SEGMENTS, 1.0))
    for j in range(SEGMENTS):
        a = 2 * j + 1
        faces.append((a, a + 1, a + 3))
        faces.append((a, a + 3, a + 2))
    with open(RING_OUT, "w", newline="\n") as f:
        f.write("# where an air bubble of the Plane of Water meets the floor (tools/make_bubble_mesh.py)\n")
        for p in v:
            f.write("v %.4f %.4f %.4f\n" % p)
        for t in vt:
            f.write("vt %.4f %.4f\n" % t)
        f.write("vn 0 1 0\n")
        for a, b, c in faces:
            f.write("f %d/%d/1 %d/%d/1 %d/%d/1\n" % (a, a, b, b, c, c))
    print("wrote %s (%d triangles)" % (RING_OUT, len(faces)))


if __name__ == "__main__":
    main()
