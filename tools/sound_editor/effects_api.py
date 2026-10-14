"""Particle effects for the editor server (the Effects tab).

Reads and writes game/nethackvoxel/mods/nhv_effects:
  effects.json     the effects (see mods/nhv/effects.lua)
  textures/*.png   built-in particle pictures (nhvfx_dot, _spark, ...) and
                   uploaded ones (names start with "nhvfx_")
"""
import json
import os
import re
import shutil

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
FX = os.path.join(ROOT, "game", "nethackvoxel", "mods", "nhv_effects")
DATA = os.path.join(FX, "effects.json")
TEXTURES = os.path.join(FX, "textures")

SHAPES = ("burst", "rise", "rain", "implode", "ring")
BUILTIN = ("dot", "spark", "star", "square", "ring")
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"
COLOR_RE = re.compile(r"^#[0-9A-Fa-f]{6}$")
HOOK_RE = re.compile(r"^[a-z0-9_]{1,80}$")


def load():
    try:
        with open(DATA, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        data = {}
    data.setdefault("version", 1)
    data.setdefault("effects", [])
    return data


def textures():
    os.makedirs(TEXTURES, exist_ok=True)
    return sorted(f for f in os.listdir(TEXTURES)
                  if f.lower().endswith(".png") and not any(f == "nhvfx_%s.png" % b for b in BUILTIN))


def _num(v, lo, hi, default):
    try:
        v = float(v)
    except (TypeError, ValueError):
        return default
    return max(lo, min(hi, v))


def _range(r, lo, hi, default):
    r = r if isinstance(r, (list, tuple)) and len(r) == 2 else default
    a, b = _num(r[0], lo, hi, default[0]), _num(r[1], lo, hi, default[1])
    return [min(a, b), max(a, b)]


def clean_layer(l):
    tex = l.get("texture") or {}
    if tex.get("builtin") in BUILTIN:
        tex = {"builtin": tex["builtin"]}
    elif tex.get("file"):
        if not re.match(r"^[A-Za-z0-9_.-]+\.png$", tex["file"]):
            raise ValueError("bad texture file name")
        tex = {"file": tex["file"]}
    elif tex.get("sheet") is not None:
        tex = {"sheet": int(tex["sheet"])}
    else:
        tex = {"builtin": "dot"}
    shape = l.get("shape") if l.get("shape") in SHAPES else "burst"
    color = l.get("color") if COLOR_RE.match(str(l.get("color", ""))) else "#FFFFFF"
    return {
        "shape": shape, "texture": tex, "color": color,
        "amount": int(_num(l.get("amount"), 1, 400, 30)),
        "duration": _num(l.get("duration"), 0.05, 10, 0.3),
        "spread": _num(l.get("spread"), 0, 4, 0.4),
        "height": _num(l.get("height"), -1, 4, 1.0),
        "speed": _range(l.get("speed"), 0, 30, [1, 3]),
        "life": _range(l.get("life"), 0.05, 10, [0.5, 1.2]),
        "size": _range(l.get("size"), 0.1, 20, [1, 2]),
        "gravity": _num(l.get("gravity"), -20, 20, 0),
        "glow": int(_num(l.get("glow"), 0, 14, 10)),
        "additive": bool(l.get("additive", True)),
        "fade": bool(l.get("fade", True)),
        "collide": bool(l.get("collide", False)),
    }


def clean_effect(e):
    eid = re.sub(r"[^a-z0-9_]+", "_", str(e.get("id", "")).lower()).strip("_")
    if not eid:
        raise ValueError("every effect needs an id")
    layers = [clean_layer(l) for l in (e.get("layers") or [])[:6] if isinstance(l, dict)]
    if not layers:
        layers = [clean_layer({})]
    triggers = sorted({t for t in (e.get("triggers") or []) if HOOK_RE.match(str(t))})
    return {"id": eid, "name": str(e.get("name") or eid)[:60], "layers": layers, "triggers": triggers}


def save(data):
    effects = [clean_effect(e) for e in data.get("effects", [])]
    ids = [e["id"] for e in effects]
    if len(ids) != len(set(ids)):
        raise ValueError("two effects have the same id")
    os.makedirs(FX, exist_ok=True)
    if os.path.exists(DATA):
        shutil.copyfile(DATA, DATA + ".bak")
    tmp = DATA + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump({"version": 1, "effects": effects}, f, indent=1)
    os.replace(tmp, DATA)
    return effects


def upload_texture(name, data):
    """Save an uploaded PNG as textures/nhvfx_<name>.png; returns the file name."""
    if not data.startswith(PNG_MAGIC):
        raise ValueError("that isn't a PNG image")
    if len(data) > 2 * 1024 * 1024:
        raise ValueError("image too large")
    base = re.sub(r"[^a-z0-9_]+", "_", name.lower().rsplit(".", 1)[0]).strip("_") or "particle"
    if not base.startswith("nhvfx_"):
        base = "nhvfx_" + base
    if base[len("nhvfx_"):] in BUILTIN:
        base += "_custom"
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
