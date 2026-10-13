"""Turn a BDF bitmap font into a TrueType font made of square pixels.

    python tools/make_pixel_font.py [in.bdf] [out.ttf]

Default: NetHack's public-domain IBM PC font (external/nethack/win/X11/
ibm.bdf, 8x14) -> game/nethackvoxel/mods/nhv/fonts/nhv_retro.ttf, the
"Retro" interface font. Each lit pixel becomes a square outline, so the
font stays sharp at any whole multiple of its pixel height (14, 28, ...).
No libraries needed: the TrueType tables are written by hand below.
"""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(ROOT, "external", "nethack", "win", "X11", "ibm.bdf")
DST = os.path.join(ROOT, "game", "nethackvoxel", "mods", "nhv", "fonts", "nhv_retro.ttf")
U = 128  # font units per pixel
NAME = "NHV Retro"


def read_bdf(path):
    """{code: (width, bbx_w, bbx_h, x_off, y_off, rows)}, ascent, descent"""
    glyphs, props = {}, {}
    cur = rows = None
    for line in open(path, encoding="latin-1"):
        parts = line.split()
        if not parts:
            continue
        key = parts[0]
        if rows is not None:
            if key == "ENDCHAR":
                cur["rows"] = rows
                if cur.get("code", -1) >= 0:
                    glyphs[cur["code"]] = cur
                cur = rows = None
            else:
                rows.append(int(parts[0], 16))
                cur["rowbits"] = len(parts[0]) * 4  # (rows are padded to whole bytes)
            continue
        if key in ("FONT_ASCENT", "FONT_DESCENT"):
            props[key] = int(parts[1])
        elif key == "FONTBOUNDINGBOX":
            props["bbx"] = [int(p) for p in parts[1:5]]
        elif key == "STARTCHAR":
            cur = {}
        elif key == "ENCODING" and cur is not None:
            cur["code"] = int(parts[1])
        elif key == "DWIDTH" and cur is not None:
            cur["dwidth"] = int(parts[1])
        elif key == "BBX" and cur is not None:
            cur["bbx"] = [int(p) for p in parts[1:5]]
        elif key == "BITMAP" and cur is not None:
            rows = []
    return glyphs, props.get("FONT_ASCENT", 11), props.get("FONT_DESCENT", 3), props["bbx"][0]


def rects(g):
    """The glyph's lit pixels as rectangles (x0, y0, x1, y1) in pixels, y up."""
    w, h, xo, yo = g["bbx"]
    nbits = g.get("rowbits", (w + 7) // 8 * 8)
    runs = []  # per row: list of (start, end)
    for r, bits in enumerate(g["rows"]):
        row, c = [], 0
        while c < w:
            if bits >> (nbits - 1 - c) & 1:
                s = c
                while c < w and bits >> (nbits - 1 - c) & 1:
                    c += 1
                row.append((s, c))
            else:
                c += 1
        runs.append(row)
    # merge the same run in consecutive rows into one rectangle
    out, open_ = [], {}
    for r, row in enumerate(runs + [[]]):
        top = yo + h - r  # y of this row's top edge
        for span in list(open_):
            if span not in row:
                out.append((xo + span[0], top, xo + span[1], open_.pop(span)))
        for span in row:
            open_.setdefault(span, top)
    return out


def glyph_data(rs):
    if not rs:
        return b"", (0, 0, 0, 0), 0, 0
    pts, ends = [], []
    for x0, y0, x1, y1 in rs:  # clockwise (y up): top-left, top-right, bottom-right, bottom-left
        pts += [(x0 * U, y1 * U), (x1 * U, y1 * U), (x1 * U, y0 * U), (x0 * U, y0 * U)]
        ends.append(len(pts) - 1)
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    box = (min(xs), min(ys), max(xs), max(ys))
    d = struct.pack(">hhhhh", len(ends), *box)
    d += struct.pack(">%dH" % len(ends), *ends) + struct.pack(">H", 0)
    d += bytes([0x01]) * len(pts)  # on-curve, 16-bit x and y deltas
    px = py = 0
    xd, yd = b"", b""
    for x, y in pts:
        xd += struct.pack(">h", x - px)
        yd += struct.pack(">h", y - py)
        px, py = x, y
    d += xd + yd
    return d, box, len(pts), len(ends)


def checksum(data):
    data += b"\0" * (-len(data) % 4)
    return sum(struct.unpack(">%dI" % (len(data) // 4), data)) & 0xFFFFFFFF


def cmap_table(codes):
    """format 4 subtable mapping each code to its glyph index (1, 2, ...)"""
    segs = []
    for gid, code in enumerate(codes, 1):
        if segs and segs[-1][1] == code - 1 and segs[-1][2] - segs[-1][0] == gid - code:
            segs[-1] = (segs[-1][0], code, segs[-1][2])  # same offset: extend the segment
        else:
            segs.append((code, code, gid))
    starts = [s[0] for s in segs] + [0xFFFF]
    ends = [s[1] for s in segs] + [0xFFFF]
    deltas = [(s[2] - s[0]) & 0xFFFF for s in segs] + [1]
    n = len(starts)
    sr = 2 ** (n.bit_length() - 1) * 2
    sub = struct.pack(">HHHHHHH", 4, 0, 0, n * 2, sr, (sr // 2).bit_length() - 1, n * 2 - sr)
    sub += struct.pack(">%dH" % n, *ends) + b"\0\0" + struct.pack(">%dH" % n, *starts)
    sub += struct.pack(">%dH" % n, *deltas) + struct.pack(">%dH" % n, *([0] * n))
    sub = sub[:2] + struct.pack(">H", len(sub)) + sub[4:]
    return struct.pack(">HHHHI", 0, 1, 3, 1, 12) + sub


def name_table():
    recs = {1: NAME, 2: "Regular", 3: NAME + " 1.0", 4: NAME, 5: "Version 1.0", 6: "NHVRetro-Regular",
            0: "Public domain (NetHack's ibm.bdf)"}
    strings, entries, off = b"", b"", 0
    for nid in sorted(recs):
        s = recs[nid].encode("utf-16-be")
        entries += struct.pack(">HHHHHH", 3, 1, 0x409, nid, len(s), off)
        strings += s
        off += len(s)
    return struct.pack(">HHH", 0, len(recs), 6 + 12 * len(recs)) + entries + strings


def build(src, dst):
    glyphs, ascent, descent, cell_w = read_bdf(src)
    # printable ASCII only: the upper half is NetHack's own mix of map
    # symbols, matching neither Latin-1 nor the IBM PC set (anything else
    # comes from the game's fallback font)
    uni = {c: c for c in glyphs if 32 <= c <= 126}
    codes = sorted(uni, key=lambda c: uni[c])
    adv = cell_w * U
    # glyph 0 (.notdef): a hollow box
    nd = [(1, 0, cell_w - 1, 1), (1, ascent - 2, cell_w - 1, ascent - 1), (1, 1, 2, ascent - 2), (cell_w - 2, 1, cell_w - 1, ascent - 2)]
    datas = [glyph_data(nd)] + [glyph_data(rects(glyphs[c])) for c in codes]
    codes = [uni[c] for c in codes]  # (glyph i + 1 is Unicode codes[i])
    glyf, loca = b"", []
    for d in datas:
        loca.append(len(glyf))
        glyf += d[0] + b"\0" * (-len(d[0]) % 4)
    loca.append(len(glyf))
    boxes = [d[1] for d in datas if d[0]]
    fbox = (min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes))
    n = len(datas)
    asc, desc = ascent * U, descent * U
    t = {}
    t["head"] = struct.pack(">IIIIHHqqhhhhHHhhh", 0x00010000, 0x00010000, 0, 0x5F0F3CF5, 0x000B,
                            (ascent + descent) * U, 0, 0, *fbox, 0, 8, 2, 1, 0)
    t["hhea"] = struct.pack(">IhhhHhhhhhhhhhhhH", 0x00010000, asc, -desc, 0, adv,
                            min(b[0] for b in boxes), 0, fbox[2], 1, 0, 0, 0, 0, 0, 0, 0, n)
    t["maxp"] = struct.pack(">IHHHHHHHHHHHHHH", 0x00010000, n, max(d[2] for d in datas),
                            max(d[3] for d in datas), 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0)
    t["OS/2"] = struct.pack(">HhHHHhhhhhhhhhhh10sIIII4sHHHhhhHHIIhhHHH", 4, adv, 400, 5, 0,
                            7 * U, 7 * U, 0, 2 * U, 7 * U, 7 * U, 0, 5 * U, U, 4 * U, 0,
                            bytes([2, 11, 6, 9, 0, 0, 0, 0, 0, 0]), 3, 0, 0, 0, b"NHV ", 0x40,
                            codes[0], min(codes[-1], 0xFFFF), asc, -desc, 0, asc, desc, 1, 0,
                            7 * U, 9 * U, 0, 32, 1)
    t["hmtx"] = b"".join(struct.pack(">Hh", adv, d[1][0]) for d in datas)
    t["cmap"] = cmap_table(codes)
    t["loca"] = struct.pack(">%dI" % len(loca), *loca)
    t["glyf"] = glyf
    t["name"] = name_table()
    t["post"] = struct.pack(">IIhhIIIII", 0x00030000, 0, -2 * U, U, 1, 0, 0, 0, 0)

    tags = sorted(t)
    nt = len(tags)
    sr = 2 ** (nt.bit_length() - 1) * 16
    head = struct.pack(">IHHHH", 0x00010000, nt, sr, (sr // 16).bit_length() - 1, nt * 16 - sr)
    off = 12 + 16 * nt
    dirs, body = b"", b""
    for tag in tags:
        d = t[tag]
        dirs += struct.pack(">4sIII", tag.encode(), checksum(d), off + len(body), len(d))
        body += d + b"\0" * (-len(d) % 4)
    font = bytearray(head + dirs + body)
    hoff = 12 + 16 * nt + sum(len(t[x]) + (-len(t[x]) % 4) for x in tags[:tags.index("head")])
    struct.pack_into(">I", font, hoff + 8, (0xB1B0AFBA - checksum(bytes(font))) & 0xFFFFFFFF)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    with open(dst, "wb") as f:
        f.write(font)
    print("%s: %d glyphs, %dx%d pixels" % (dst, n, cell_w, ascent + descent))


if __name__ == "__main__":
    build(sys.argv[1] if len(sys.argv) > 1 else SRC, sys.argv[2] if len(sys.argv) > 2 else DST)
