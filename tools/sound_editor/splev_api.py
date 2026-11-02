"""Special levels for the editor server (the Special levels tab): a map of
each special level with its hand-built parts, for reading, not editing.

Reads:
  splev_levels.txt  every special level whole, as NetHack built it once
                    (tools/make_splev_templates.py writes it): its terrain
                    before any flip, its fixed regions, stair, branch and
                    teleport regions, stairs and portals
  game/nethackvoxel/mods/nhv/splev_templates.txt
                    the fixed regions the prefab editor builds (areas.lua)
  mod_data/nhv/areas/*.dat
                    how much of each one is built
  external/nethack/dat/*.lua
                    how each level file places its maps and fills the rest
"""
import os
import re

import sky_api

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
LEVELS = os.path.join(HERE, "splev_levels.txt")
TEMPLATES = sky_api.TEMPLATES
AREAS = os.path.join(ROOT, "external", "luanti", "mod_data", "nhv", "areas")
DAT = sky_api.DAT

COLNO, ROWNO = 80, 21

# what fills a level before its maps go in (des.level_init's style)
FILLS = {
    "mazegrid": "a maze NetHack makes each game",
    "maze": "a maze NetHack makes each game",
    "mines": "a Mines-style cave NetHack makes each game",
    "swamp": "swamp NetHack makes each game",
}
SOLID = {" ": "solid rock", ".": "floor", "#": "corridor", "}": "water", "L": "lava",
         "A": "air", "C": "cloud", "-": "wall", "|": "wall", "W": "water", "w": "water",
         "I": "ice", "T": "trees", "F": "iron bars"}
HALIGN = {"left": "at the left edge", "half-left": "in the left half", "center": "in the middle",
          "half-right": "in the right half", "right": "at the right edge"}
VALIGN = {"top": "at the top", "center": "centred top to bottom", "bottom": "at the bottom"}


def _lua(proto):
    try:
        with open(os.path.join(DAT, proto + ".lua"), encoding="utf-8") as f:
            text = f.read()
    except OSError:
        return {}
    # (comments out: they mention des.map and styles too)
    text = re.sub(r"--\[\[.*?\]\]", "", text, flags=re.S)
    text = re.sub(r"--[^\n]*", "", text)
    out = {}
    m = re.search(r"des\.level_init\(\s*\{([^}]*)\}", text)
    if m:
        st = re.search(r'style\s*=\s*"(\w+)"', m.group(1))
        fg = re.search(r'fg\s*=\s*"(.)"', m.group(1))
        out["style"] = st.group(1) if st else None
        out["fg"] = fg.group(1) if fg else " "
    m = re.search(r"des\.level_flags\(([^)]*)\)", text)
    if m:
        out["flags"] = re.findall(r'"([^"]+)"', m.group(1))
    maps = []
    for m in re.finditer(r"des\.map\(\s*(\{[^\[]*?)?(?:map\s*=\s*)?\[\[", text):
        opts = m.group(1) or ""
        mp = {}
        for k in ("halign", "valign"):
            v = re.search(k + r'\s*=\s*"([\w-]+)"', opts)
            if v:
                mp[k] = v.group(1)
        for k in ("x", "y"):
            v = re.search(r"\b" + k + r"\s*=\s*(\d+)", opts)
            if v:
                mp[k] = int(v.group(1))
        maps.append(mp)
    out["maps"] = maps
    out["mazewalk"] = len(re.findall(r"des\.mazewalk\(", text))
    return out


def _placement(mp):
    if "x" in mp and "y" in mp:
        return "always at %d, %d" % (mp["x"], mp["y"])
    h = HALIGN.get(mp.get("halign", "center"), mp.get("halign"))
    v = VALIGN.get(mp.get("valign", "center"), mp.get("valign"))
    return "%s, %s" % (h, v)


def _outside(info):
    st = info.get("style")
    if st in FILLS:
        return FILLS[st]
    if st == "solidfill":
        return "%s, with whatever else the level file adds there (some of it at random)" \
            % SOLID.get(info.get("fg", " "), "solid fill")
    if st:
        return "filled by NetHack (%s)" % st
    return "made by NetHack as on an ordinary level (rooms and corridors)"


def _templates():
    out = {}
    try:
        with open(TEMPLATES, encoding="utf-8") as f:
            for line in f:
                p = line.split()
                if len(p) >= 6 and not line.startswith("#"):
                    out[(p[0], int(p[1]))] = {"w": int(p[4]), "h": int(p[5])}
    except OSError:
        pass
    return out


def _built(proto, n, w, h):
    """how many squares of an area are built (0 if none or no file)"""
    path = os.path.join(AREAS, re.sub(r"[^\w-]", "_", "%s#%d" % (proto, n)) + ".dat")
    try:
        with open(path, encoding="utf-8") as f:
            return sum(1 for ln in f if "\t" in ln and not ln.startswith("palette"))
    except OSError:
        return 0


def load():
    levels = {}
    try:
        with open(LEVELS, encoding="utf-8") as f:
            lines = f.read().splitlines()
    except OSError:
        return {"levels": [], "missing": True}
    for ln in lines:
        p = ln.split()
        if len(p) < 3 or ln.startswith("#"):
            continue
        kind, proto = p[0], p[1]
        lv = levels.setdefault(proto, {"proto": proto, "allow": 0, "typ": "", "parts": [],
                                       "regions": [], "stairs": [], "portals": []})
        if kind == "L":
            lv["allow"], lv["typ"] = int(p[2]), p[3]
        elif kind == "Q":
            lv["parts"].append({"n": int(p[2]), "x": int(p[3]), "y": int(p[4]),
                                "w": int(p[5]), "h": int(p[6])})
        elif kind == "R":
            v = [int(x) for x in p[2:]]
            lv["regions"].append({"t": v[0], "area": v[1:5],
                                  "except": v[5:9] if any(v[5:9]) else None})
        elif kind == "S":
            v = [int(x) for x in p[2:]]
            lv["stairs"].append({"x": v[0], "y": v[1], "up": bool(v[2]), "ladder": bool(v[3]),
                                 "branch": bool(v[4])})
        elif kind == "P":
            lv["portals"].append({"x": int(p[2]), "y": int(p[3])})

    tpl = _templates()
    groups = []
    seen = set()
    order = []
    for g in sky_api.level_names():
        for l in g["levels"]:
            if not l.get("family"):
                order.append((g["group"], l["id"], l["name"]))
    by_lower = {p.lower(): p for p in levels}
    for group, lid, name in order:
        proto = by_lower.get(lid)
        if not proto or proto in seen:
            continue
        seen.add(proto)
        groups.append((group, proto, name))
    for proto in sorted(levels):
        if proto not in seen:
            groups.append(("Others", proto, proto))

    out = []
    for group, proto, name in groups:
        lv = levels[proto]
        info = _lua(proto)
        maps = info.get("maps", [])
        for part in lv["parts"]:
            t = tpl.get((proto, part["n"]))
            part["template"] = bool(t)
            part["built"] = _built(proto, part["n"], part["w"], part["h"]) if t else 0
            part["squares"] = part["w"] * part["h"]
            part["id"] = proto if len(lv["parts"]) == 1 else "%s#%d" % (proto, part["n"])
            # (the level file's maps in order, when each part is one of them)
            if len(maps) == len(lv["parts"]):
                part["placed"] = _placement(maps[part["n"] - 1])
        lv.update({"group": group, "name": name, "outside": _outside(info),
                   "flags": info.get("flags", []), "style": info.get("style")})
        out.append(lv)
    return {"levels": out, "cols": COLNO, "rows": ROWNO}
