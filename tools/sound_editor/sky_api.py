"""Skies for the editor server (the Sky tab).

Reads and writes game/nethackvoxel/mods/nhv_sky:
  skies.json       the skies and which level gets which (see mods/nhv/sky.lua)
  textures/*.png   the layer pictures (uploaded ones' names start "nhv_sky_")
"""
import json
import os
import re
import shutil

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
SKY = os.path.join(ROOT, "game", "nethackvoxel", "mods", "nhv_sky")
DATA = os.path.join(SKY, "skies.json")
TEXTURES = os.path.join(SKY, "textures")
TEMPLATES = os.path.join(ROOT, "game", "nethackvoxel", "mods", "nhv", "splev_templates.txt")
# NetHack's special levels (one .lua each)
DAT = os.path.join(ROOT, "external", "nethack", "dat")

PNG_MAGIC = b"\x89PNG\r\n\x1a\n"
COLOR_RE = re.compile(r"^#[0-9A-Fa-f]{6}$")
FILE_RE = re.compile(r"^[A-Za-z0-9_.-]+\.png$")
LEVEL_RE = re.compile(r"^[a-z0-9_-]{1,40}$")


def load():
    try:
        with open(DATA, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        data = {}
    data.setdefault("version", 1)
    data.setdefault("skies", [])
    data.setdefault("levels", {})
    return data


def textures():
    os.makedirs(TEXTURES, exist_ok=True)
    return sorted(f for f in os.listdir(TEXTURES) if f.lower().endswith(".png"))


# what the special levels are called (as areas.lua's names)
LEVEL_NAMES = {
    "minetn-1": "Frontier Town (or Orcish Town)", "minetn-2": "Town Square",
    "minetn-3": "Alley Town", "minetn-4": "College Town", "minetn-5": "Grotto",
    "minetn-6": "Bustling Town", "minetn-7": "Bazaar Town", "minefill": "Mines filler levels",
    "oracle": "The Oracle", "castle": "The Castle", "valley": "Valley of the Dead",
    "sanctum": "Moloch's Sanctum", "astral": "Astral Plane", "earth": "Plane of Earth",
    "air": "Plane of Air", "fire": "Plane of Fire", "water": "Plane of Water",
    "knox": "Fort Ludios", "wizard1": "Wizard's Tower (bottom)",
    "wizard2": "Wizard's Tower (middle)", "wizard3": "Wizard's Tower (top)",
    "fakewiz1": "Fake Wizard's Tower 1", "fakewiz2": "Fake Wizard's Tower 2",
    "tower1": "Vlad's Tower (bottom)", "tower2": "Vlad's Tower (middle)",
    "tower3": "Vlad's Tower (top)", "asmodeus": "Asmodeus's lair",
    "baalz": "Baalzebub's lair", "juiblex": "Juiblex's swamp", "orcus": "Orcus Town",
    "hellfill": "Gehennom filler mazes",
}
FAMILY_NAMES = {"medusa": "Medusa's Island", "bigrm": "Big Room", "minetn": "Minetown",
                "minend": "Mines' End", "tut": "Tutorial"}
ROLES = {"arc": "Archeologist", "bar": "Barbarian", "cav": "Caveman", "hea": "Healer",
         "kni": "Knight", "mon": "Monk", "pri": "Priest", "ran": "Ranger", "rog": "Rogue",
         "sam": "Samurai", "tou": "Tourist", "val": "Valkyrie", "wiz": "Wizard"}
QUEST_PARTS = {"strt": "home", "loca": "locate", "fila": "filler A", "filb": "filler B",
               "goal": "goal"}
GROUPS = [
    ("The Dungeons of Doom", ("oracle", "bigrm", "medusa", "castle")),
    ("The Gnomish Mines", ("minefill", "minetn", "minend")),
    ("Sokoban", ("soko",)),
    ("The Quest", tuple(ROLES)),
    ("Fort Ludios", ("knox",)),
    ("Gehennom", ("valley", "hellfill", "juiblex", "orcus", "asmodeus", "baalz",
                  "wizard", "fakewiz", "sanctum")),
    ("Vlad's Tower", ("tower",)),
    ("The Elemental Planes", ("earth", "air", "fire", "water", "astral")),
    ("The Tutorial", ("tut",)),
]
NOT_LEVELS = {"dungeon", "nhcore", "nhlib", "quest", "themerms"}


def _level_name(p):
    fam, _, part = p.partition("-")
    if p in LEVEL_NAMES:
        return LEVEL_NAMES[p]
    if fam in ROLES and part in QUEST_PARTS:
        return "%s quest: %s" % (ROLES[fam], QUEST_PARTS[part])
    m = re.match(r"^soko(\d)-(\d)$", p)
    if m:
        return "Sokoban level %s, version %s" % m.groups()
    if fam in FAMILY_NAMES and part:
        return "%s %s" % (FAMILY_NAMES[fam], part)
    return p


def _family_name(fam):
    if fam in ROLES:
        return "%s quest (all its levels)" % ROLES[fam]
    m = re.match(r"^soko(\d)$", fam)
    if m:
        return "Sokoban level %s (both versions)" % m.group(1)
    return "%s (any of them)" % FAMILY_NAMES.get(fam, fam)


def level_names():
    """The levels a sky can be picked for, grouped by where they are:
    [{"group": ..., "levels": [{"id", "name", "family" (a set of
    variants: "medusa"), "of" (a variant's family)}]}]. Ids are what the game
    looks up: the variant ("medusa-2", "arc-strt") or its family ("medusa",
    "arc"); every other level gets the default sky."""
    protos = set()
    try:
        for f in os.listdir(DAT):
            if f.endswith(".lua") and f[:-4] not in NOT_LEVELS:
                protos.add(f[:-4].lower())
    except OSError:
        pass
    try:  # (the hand-built areas' list, if NetHack's own isn't here)
        with open(TEMPLATES, encoding="utf-8") as f:
            for line in f:
                v = line.split(" ", 1)[0].strip().lower()
                if LEVEL_RE.match(v):
                    protos.add(v)
    except OSError:
        pass

    def natural(p):
        part = p.partition("-")[2]
        if part in QUEST_PARTS:  # (a quest's levels in the order you meet them)
            return [p.partition("-")[0], list(QUEST_PARTS).index(part)]
        return [int(t) if t.isdigit() else t for t in re.split(r"(\d+)", p)]

    fams = {}
    for p in protos:
        fam = p.split("-", 1)[0]
        if "-" in p:
            fams.setdefault(fam, []).append(p)
    out, used = [], set()
    for title, starts in GROUPS:
        levels = []
        for st in starts:
            for p in sorted((p for p in protos if p not in used and (p == st or p.split("-", 1)[0] == st
                             or (st in ("soko", "wizard", "fakewiz", "tower") and p.startswith(st)))),
                            key=natural):
                fam = p.split("-", 1)[0]
                if "-" in p and fam not in used:
                    used.add(fam)
                    levels.append({"id": fam, "name": _family_name(fam), "family": True})
                used.add(p)
                levels.append({"id": p, "name": _level_name(p), "of": fam if "-" in p else None})
        if levels:
            out.append({"group": title, "levels": levels})
    rest = sorted(p for p in protos if p not in used)
    if rest:
        out.append({"group": "Others", "levels": [{"id": p, "name": _level_name(p)} for p in rest]})
    return out


def _num(v, lo, hi, default):
    try:
        v = float(v)
    except (TypeError, ValueError):
        return default
    return max(lo, min(hi, v))


def _color(v, default):
    return v if COLOR_RE.match(str(v or "")) else default


def clean_layer(l):
    l = l if isinstance(l, dict) else {}
    tex = str(l.get("texture") or "")
    if tex and not FILE_RE.match(tex):
        raise ValueError("bad texture file name")
    sp = l.get("speed") if isinstance(l.get("speed"), (list, tuple)) and len(l.get("speed")) == 2 else [0, 0]
    return {
        "kind": "texture" if l.get("kind") == "texture" else "generated",
        "texture": tex,
        "speed": [_num(sp[0], -2, 2, 0), _num(sp[1], -2, 2, 0)],
        "scale": _num(l.get("scale"), 0.1, 40, 1),
        "opacity": _num(l.get("opacity"), 0, 1, 1),
        "tint": _color(l.get("tint"), "#FFFFFF"),
        "see_through_black": bool(l.get("see_through_black", False)),
        # (generated clouds)
        "coverage": _num(l.get("coverage"), 0, 1, 0.5),
        "softness": _num(l.get("softness"), 0, 1, 0.15),
        "detail": int(_num(l.get("detail"), 1, 6, 4)),
        "shade": _color(l.get("shade"), "#666673"),
    }


def clean_sky(s):
    sid = re.sub(r"[^a-z0-9_]+", "_", str(s.get("id", "")).lower()).strip("_")
    if not sid:
        raise ValueError("every sky needs an id")
    layers = (s.get("layers") or [])[:2]
    while len(layers) < 2:
        layers.append({})
    h = s.get("horizon") if isinstance(s.get("horizon"), dict) else {}
    return {
        "id": sid,
        "name": str(s.get("name") or sid)[:60],
        "layers": [clean_layer(l) for l in layers],
        "horizon": {"color": _color(h.get("color"), "#000000"), "fade": _num(h.get("fade"), 0, 1, 0.6)},
        "pixels": int(_num(s.get("pixels"), 0, 512, 64)),
        "fog_color": _color(s.get("fog_color"), "#000000"),
        "daynight": bool(s.get("daynight", False)),
        "sun": bool(s.get("sun", True)),
        "moon": bool(s.get("moon", True)),
        "stars": bool(s.get("stars", True)),
    }


def save(data):
    skies = [clean_sky(s) for s in data.get("skies", []) if isinstance(s, dict)]
    ids = [s["id"] for s in skies]
    if len(ids) != len(set(ids)):
        raise ValueError("two skies have the same id")
    levels = {}
    for k, v in (data.get("levels") or {}).items():
        if LEVEL_RE.match(str(k)) and v in ids:
            levels[str(k)] = v
    os.makedirs(SKY, exist_ok=True)
    if os.path.exists(DATA):
        shutil.copyfile(DATA, DATA + ".bak")
    tmp = DATA + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump({"version": 1, "skies": skies, "levels": levels}, f, indent=1)
    os.replace(tmp, DATA)
    return {"skies": skies, "levels": levels}


def upload_texture(name, data):
    """Save an uploaded PNG as textures/nhv_sky_<name>.png; returns the file name."""
    if not data.startswith(PNG_MAGIC):
        raise ValueError("that isn't a PNG image")
    if len(data) > 4 * 1024 * 1024:
        raise ValueError("image too large")
    base = re.sub(r"[^a-z0-9_]+", "_", name.lower().rsplit(".", 1)[0]).strip("_") or "layer"
    if not base.startswith("nhv_sky_"):
        base = "nhv_sky_" + base
    fname = base[:60] + ".png"
    os.makedirs(TEXTURES, exist_ok=True)
    with open(os.path.join(TEXTURES, fname), "wb") as f:
        f.write(data)
    return fname


def texture_path(fname):
    if not FILE_RE.match(fname):
        return None
    p = os.path.join(TEXTURES, fname)
    return p if os.path.isfile(p) else None
