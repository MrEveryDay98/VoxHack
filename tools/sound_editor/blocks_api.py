"""Block editor data for the editor server (the Blocks tab).

Reads and writes game/nethackvoxel/mods/nhv_blocks:
  blocks.json      the block definitions (see mods/nhv/custom_blocks.lua)
  textures/*.png   pictures uploaded for blocks (names start with "nhvb_")
and serves the sprite sheet so a block can use one of its sprites.
"""
import json
import os
import re
import shutil

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
MODS = os.path.join(ROOT, "game", "nethackvoxel", "mods")
BLOCKS = os.path.join(MODS, "nhv_blocks")
DATA = os.path.join(BLOCKS, "blocks.json")
TEXTURES = os.path.join(BLOCKS, "textures")
SHEET = os.path.join(MODS, "nhv_tiles", "textures", "nhv_tiles.png")
TILENAMES = os.path.join(MODS, "nhv_tiles", "tilenames.lua")

SHAPES = ("cube", "x", "floor", "slab", "pane", "object", "invisible")
SIDES = ("top", "bottom", "east", "west", "north", "south")
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


def sheet_info():
    """cols, rows and the name of each sprite position."""
    info = {"cols": 48, "rows": 25, "names": {}}
    try:
        s = open(TILENAMES, encoding="utf-8").read()
        m = re.search(r"cols = (\d+)", s)
        if m:
            info["cols"] = int(m.group(1))
        m = re.search(r"rows = (\d+)", s)
        if m:
            info["rows"] = int(m.group(1))
        names = s.split("sheet_names = {", 1)[1].split("\n  },", 1)[0]
        for i, name in re.findall(r'\[(\d+)\] = "((?:[^"\\]|\\.)*)"', names):
            info["names"][i] = name
    except (OSError, IndexError):
        pass
    return info


def load():
    try:
        with open(DATA, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        data = {}
    data.setdefault("version", 1)
    data.setdefault("blocks", [])
    return data


def textures():
    os.makedirs(TEXTURES, exist_ok=True)
    return sorted(f for f in os.listdir(TEXTURES) if f.lower().endswith(".png"))


def clean_block(b):
    """Validate one block definition (raises ValueError)."""
    bid = re.sub(r"[^a-z0-9_]+", "_", str(b.get("id", "")).lower()).strip("_")
    if not bid:
        raise ValueError("every block needs an id")
    shape = b.get("shape", "cube")
    if shape not in SHAPES:
        raise ValueError("unknown shape: %s" % shape)
    tex = b.get("texture") or {}
    if tex.get("file"):
        if not re.match(r"^[A-Za-z0-9_.-]+\.png$", tex["file"]):
            raise ValueError("bad texture file name")
        tex = {"file": tex["file"]}
    elif tex.get("sheet") is not None:
        tex = {"sheet": int(tex["sheet"])}
    else:
        tex = {}
    dmg = str(b.get("damage", "")).strip()
    if dmg and not re.match(r"^\d*d\d+\s*([+-]\s*\d+)?$|^\d+$", dmg):
        raise ValueError("damage must be like 1d4, 2d6+1 or 3")
    return {
        "id": bid, "name": str(b.get("name") or bid)[:60], "shape": shape, "texture": tex,
        "scale": max(0.1, min(4.0, float(b.get("scale") or 1))),
        "solid": bool(b.get("solid")), "climbable": bool(b.get("climbable")),
        "light": max(0, min(14, int(b.get("light") or 0))),
        "damage": dmg, "repeat": max(0.0, float(b.get("repeat") or 0)),
        "cause": str(b.get("cause") or "")[:60],
        # sides whose back is drawn too (seen from inside the block)
        "backfaces": {s: True for s in SIDES if (b.get("backfaces") or {}).get(s)},
    }


def save(data):
    blocks = [clean_block(b) for b in data.get("blocks", [])]
    ids = [b["id"] for b in blocks]
    if len(ids) != len(set(ids)):
        raise ValueError("two blocks have the same id")
    os.makedirs(BLOCKS, exist_ok=True)
    if os.path.exists(DATA):
        shutil.copyfile(DATA, DATA + ".bak")
    tmp = DATA + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump({"version": 1, "blocks": blocks}, f, indent=1)
    os.replace(tmp, DATA)
    return blocks


def upload_texture(name, data):
    """Save an uploaded PNG as textures/nhvb_<name>.png; returns the file name."""
    if not data.startswith(PNG_MAGIC):
        raise ValueError("that isn't a PNG image")
    if len(data) > 2 * 1024 * 1024:
        raise ValueError("image too large")
    base = re.sub(r"[^a-z0-9_]+", "_", name.lower().rsplit(".", 1)[0]).strip("_") or "texture"
    if not base.startswith("nhvb_"):
        base = "nhvb_" + base
    fname = base[:60] + ".png"
    os.makedirs(TEXTURES, exist_ok=True)
    with open(os.path.join(TEXTURES, fname), "wb") as f:
        f.write(data)
    return fname


def texture_path(fname):
    if not re.match(r"^[A-Za-z0-9_.-]+\.png$", fname):
        return None
    p = os.path.join(TEXTURES, fname)
    return p if os.path.isfile(p) else None
