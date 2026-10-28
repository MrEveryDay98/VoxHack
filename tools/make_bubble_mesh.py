"""Write the Plane of Water's air bubble meshes (nhv/bubbles.lua):
  models/nhv_bubble.obj       a smooth sphere, with normals and texture
                              coordinates
  models/nhv_bubble_ring_NN.obj  a flat ring where a bubble meets the
                              floor - its edge, to walk up to - in pieces,
                              fading toward the middle

Radius 5 units: a mesh's units are tenths of a node, so at visual size 1
it is one node across - bubbles.lua stretches it to each bubble's size.

    python -I tools/make_bubble_mesh.py
"""
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
MODELS = os.path.join(HERE, "..", "game", "nethackvoxel", "mods", "nhv", "models")
OUT = os.path.join(MODELS, "nhv_bubble.obj")
SECTORS = 48  # (the ring's pieces)
UV_REPEAT = 0.6  # (the band textures' repeats per mesh unit)
# the bands from the edge in, as parts of the radius R (bubbles.lua textures
# them bright to faint)
BANDS = (1.0, 0.97, 0.92, 0.85, 0.75, 0.6)

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
    """The ring in SECTORS pieces (models/nhv_bubble_ring_NN.obj), each in
    BANDS bands from its edge in - textured from bright to faint, so it
    fades toward the middle; a piece inside another bubble is left out."""
    for old in os.listdir(MODELS):
        if old.startswith("nhv_bubble_ring"):
            os.remove(os.path.join(MODELS, old))
    steps = 3  # (arc steps in a piece)
    for k in range(SECTORS):
        v, vt, groups = [], [], []
        for band in range(len(BANDS) - 1):
            r0, r1 = BANDS[band], BANDS[band + 1]
            faces = []
            for st in range(steps):
                a0 = 2 * math.pi * (k + st / steps) / SECTORS
                a1 = 2 * math.pi * (k + (st + 1) / steps) / SECTORS
                base = len(v) + 1
                for a, r in ((a0, r0), (a0, r1), (a1, r1), (a1, r0)):
                    x, z = R * r * math.cos(a), R * r * math.sin(a)
                    v.append((x, 0.0, z))
                    # (the texture repeats across it: bubbles.lua's bands
                    # are dither patterns, a fade in solid pixels)
                    vt.append((x * UV_REPEAT, z * UV_REPEAT))
                faces.append((base, base + 1, base + 2))
                faces.append((base, base + 2, base + 3))
            groups.append(faces)
        out = os.path.join(MODELS, "nhv_bubble_ring_%02d.obj" % k)
        with open(out, "w", newline="\n") as f:
            f.write("# piece %d of the ring where an air bubble meets the floor (tools/make_bubble_mesh.py)\n" % k)
            for p in v:
                f.write("v %.4f %.4f %.4f\n" % p)
            for t in vt:
                f.write("vt %.4f %.4f\n" % t)
            f.write("vn 0 1 0\n")
            for band, faces in enumerate(groups):
                f.write("g band%d\nusemtl band%d\n" % (band, band))
                for a, b2, c in faces:
                    f.write("f %d/%d/1 %d/%d/1 %d/%d/1\n" % (a, a, b2, b2, c, c))
    print("wrote %d ring pieces, %d bands each" % (SECTORS, len(BANDS) - 1))


if __name__ == "__main__":
    main()
