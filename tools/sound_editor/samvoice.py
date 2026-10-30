"""SAM voices for the VoxHack Editor.

Speakers ticked "Speak live with SAM" in Voice casting are voiced by SAM
(Software Automatic Mouth, 1982), which is built into the game's engine:
it reads each line's real text as it happens, so nothing is recorded here.
The editor sets each speaker's SAM voice, edits the pronunciation dictionary
(mods/nhv_sounds/sam_dictionary.txt) and previews with build/sam/samtool.exe
(made by tools/deploy.sh from the engine's own SAM code, so a preview
sounds as the game will).

voice_cast.json:
  speakers: {name: {"sam": {live, voice, speed, pitch, throat, mouth, sing,
             volume, smooth, tone, variation, female, size,
             effects: [{type, <param>: value, off}]}}}
  lines:    {id: {cast (voiced as another speaker), sam_voice (one of
             SAM's named voices), sam_text (what SAM reads instead of the
             game's text; may hold {PHONEMES})}}
"""
import json
import os
import struct
import subprocess
import wave

NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)
SAMPLE_TEXT = "Hello, adventurer! Welcome to the Dungeons of Doom. Mind the floating eye."
DEFAULT_CAST = {"version": 3, "speakers": {}, "lines": {}}

# the classic voices from SAM's manual (sound.lua has the same list)
SAM_VOICES = {
    "SAM": {"speed": 72, "pitch": 64, "throat": 128, "mouth": 128},
    "Elf": {"speed": 72, "pitch": 64, "throat": 110, "mouth": 160},
    "Little Robot": {"speed": 92, "pitch": 60, "throat": 190, "mouth": 190},
    "Stuffy Guy": {"speed": 82, "pitch": 72, "throat": 110, "mouth": 105},
    "Little Old Lady": {"speed": 82, "pitch": 32, "throat": 145, "mouth": 145},
    "Extra-Terrestrial": {"speed": 100, "pitch": 64, "throat": 150, "mouth": 200},
}
KEYS = ("speed", "pitch", "throat", "mouth")


def _p(key, label, lo, hi, step, default, unit=""):
    return {"key": key, "label": label, "min": lo, "max": hi, "step": step, "default": default, "unit": unit}


# Effects after SAM speaks, applied in order by the engine (sam_speech.cpp
# has the same names, parameters, ranges and defaults).
EFFECTS = {
    "echo": {"name": "Echo", "tip": "Distinct repeats: a cave, a well, a voice from far off.",
             "params": [_p("delay", "Delay", 20, 1500, 10, 250, " ms"), _p("decay", "Decay", 0.05, 0.95, 0.05, 0.4),
                        _p("repeats", "Repeats", 1, 8, 1, 3)]},
    "reverb": {"name": "Reverb", "tip": "A room around the voice, from a closet to a great hall.",
               "params": [_p("room", "Room size", 0, 100, 1, 60, "%"), _p("mix", "Wet", 0, 100, 1, 35, "%")]},
    "chorus": {"name": "Chorus", "tip": "Several voices at once, slightly apart.",
               "params": [_p("depth", "Depth", 0.5, 15, 0.5, 3, " ms"), _p("rate", "Rate", 0.05, 8, 0.05, 0.8, " Hz"),
                          _p("mix", "Wet", 0, 100, 1, 50, "%")]},
    "vibrato": {"name": "Vibrato", "tip": "The pitch wobbles: old, unsteady, unearthly.",
                "params": [_p("depth", "Depth", 0.2, 10, 0.1, 2, " ms"), _p("rate", "Rate", 0.5, 20, 0.5, 5, " Hz")]},
    "tremolo": {"name": "Tremolo", "tip": "The volume wobbles.",
                "params": [_p("rate", "Rate", 0.5, 30, 0.5, 6, " Hz"), _p("depth", "Depth", 0, 100, 1, 50, "%")]},
    "distortion": {"name": "Distortion", "tip": "Overdriven and gritty.",
                   "params": [_p("drive", "Drive", 0, 40, 1, 12, " dB")]},
    "bitcrush": {"name": "Bitcrusher", "tip": "Even more lo-fi: fewer bits, a lower sample rate.",
                 "params": [_p("bits", "Bits", 1, 16, 1, 6), _p("downsample", "Downsample", 1, 16, 1, 2, "x")]},
    "robot": {"name": "Robot", "tip": "Ring modulation: the voice times a tone, a buzzing machine.",
              "params": [_p("freq", "Tone", 10, 2000, 5, 60, " Hz"), _p("mix", "Wet", 0, 100, 1, 70, "%")]},
    "lowpass": {"name": "Low-pass", "tip": "Muffled: behind a door, underwater.",
                "params": [_p("freq", "Cutoff", 100, 10000, 50, 3000, " Hz")]},
    "highpass": {"name": "High-pass", "tip": "Thin and small: a radio, a tiny creature.",
                 "params": [_p("freq", "Cutoff", 20, 5000, 10, 300, " Hz")]},
    "gain": {"name": "Volume", "tip": "Louder or quieter by a fixed amount.",
             "params": [_p("db", "Gain", -30, 30, 0.5, 0, " dB")]},
}

# starting points for a speaker's effects
EFFECT_PRESETS = {
    "Cave": [{"type": "echo", "delay": 320, "decay": 0.45, "repeats": 4}, {"type": "reverb", "room": 55, "mix": 25}],
    "Great hall": [{"type": "reverb", "room": 90, "mix": 45}],
    "Distant voice": [{"type": "lowpass", "freq": 1800}, {"type": "echo", "delay": 500, "decay": 0.35, "repeats": 2},
                      {"type": "gain", "db": -4}],
    "Radio": [{"type": "highpass", "freq": 400}, {"type": "lowpass", "freq": 3000}, {"type": "distortion", "drive": 10}],
    "Ghost": [{"type": "vibrato", "depth": 3, "rate": 3}, {"type": "reverb", "room": 80, "mix": 55},
              {"type": "highpass", "freq": 250}],
    "Robot": [{"type": "robot", "freq": 55, "mix": 80}],
    "Divine": [{"type": "chorus", "depth": 4, "rate": 0.5, "mix": 50}, {"type": "reverb", "room": 95, "mix": 50}],
    "Demonic": [{"type": "distortion", "drive": 14}, {"type": "lowpass", "freq": 2500},
                {"type": "reverb", "room": 70, "mix": 30}],
}


def effect_chain(effects):
    """[{type, param: value...}] -> "echo:delay=250:decay=0.4/reverb:room=60"
    (switched-off effects and unknown ones left out; sound.lua does the same)"""
    out = []
    for fx in effects or []:
        if not isinstance(fx, dict) or fx.get("off") or fx.get("type") not in EFFECTS:
            continue
        parts = [fx["type"]]
        for p in EFFECTS[fx["type"]]["params"]:
            try:
                v = float(fx.get(p["key"], p["default"]))
            except (TypeError, ValueError):
                v = p["default"]
            parts.append("%s=%g" % (p["key"], v))
        out.append(":".join(parts))
    return "/".join(out)


def migrate_cast(cast):
    """Casts from the Kokoro / ElevenLabs editor: only SAM's parts stay. A
    line's edited spoken text becomes what SAM reads for it."""
    for name, sc in list(cast.get("speakers", {}).items()):
        for k in list(sc):
            if k != "sam":
                del sc[k]
        if not sc:
            del cast["speakers"][name]
    for line_id, ln in list(cast.get("lines", {}).items()):
        if ln.get("spoken") and not ln.get("sam_text"):
            ln["sam_text"] = ln["spoken"]
        for k in list(ln):
            if k not in ("cast", "sam_voice", "sam_text"):
                del ln[k]
        if not ln:
            del cast["lines"][line_id]
    for k in list(cast):
        if k not in ("version", "speakers", "lines"):
            del cast[k]
    cast["version"] = 3
    return cast


def _clamp(v):
    return max(1, min(255, int(round(v))))


def monster_dice(m_id):
    """The same four numbers in [-1, 1] sound.lua gives a monster."""
    h = (m_id * 2654435761) % 4294967296
    out = []
    for _ in range(4):
        d = h % 1000
        h = h // 1000 + d * 7919
        out.append(d / 999 * 2 - 1)
    return out


def settings_for(sam, m_id=0, female=False):
    """A speaker's SAM settings as the game works them out for a monster
    (m_id) of that speaker: its variation, and higher if female."""
    sam = sam or {}
    base = SAM_VOICES.get(sam.get("voice") or "SAM", SAM_VOICES["SAM"])
    st = {}
    for k in KEYS:
        try:
            st[k] = float(sam.get(k, base[k]))
        except (TypeError, ValueError):
            st[k] = base[k]
    if m_id:
        var = float(sam.get("variation", 25) or 0) / 100
        d1, d2, d3, d4 = monster_dice(m_id)
        st["pitch"] += d1 * var * 14
        st["speed"] += d2 * var * 10
        st["throat"] += d3 * var * 24
        st["mouth"] += d4 * var * 24
    if female:
        st["pitch"] -= float(sam.get("female", 12) or 0)
    st = {k: _clamp(v) for k, v in st.items()}
    st.update(sing=bool(sam.get("sing")), smooth=bool(sam.get("smooth")), hifi=bool(sam.get("hifi")),
              tuning={k: int(sam.get(k, 100) or 0) for k in HIFI_TUNING},
              tone=sam.get("tone") is not False,
              effects=effect_chain(sam.get("effects")))
    return st


# hi-fi's tuning (percent, 100 as made): the voice casting's sliders, samtool's flags
HIFI_TUNING = ("bright", "breath", "movement", "hiss")

class Voices:
    def __init__(self, root, mod):
        self.cast_path = os.path.join(mod, "voice_cast.json")
        self.dict_path = os.path.join(mod, "sam_dictionary.txt")
        self.tool = os.path.join(root, "build", "sam", "samtool.exe")
        self.work = os.path.join(root, "voice_work")
        self.sample_path = os.path.join(self.work, "sam_sample.wav")

    # -- files
    def load_cast(self):
        try:
            with open(self.cast_path, encoding="utf-8") as f:
                cast = json.load(f)
        except (OSError, ValueError):
            cast = json.loads(json.dumps(DEFAULT_CAST))
        for k, v in DEFAULT_CAST.items():
            cast.setdefault(k, json.loads(json.dumps(v)))
        if cast.get("version", 1) < 3:
            migrate_cast(cast)
        return cast

    def load_dict(self):
        try:
            with open(self.dict_path, encoding="utf-8") as f:
                return f.read()
        except OSError:
            return ""

    def save_dict(self, text):
        tmp = self.dict_path + ".tmp"
        with open(tmp, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        os.replace(tmp, self.dict_path)

    # -- SAM
    def installed(self):
        return os.path.exists(self.tool)

    def _run(self, st, text, extra):
        if not self.installed():
            raise RuntimeError("SAM's preview tool isn't built: run tools/deploy.sh (it makes build/sam/samtool.exe)")
        args = [self.tool, "--dict", self.dict_path] + [x for k in KEYS for x in ("--" + k, str(st[k]))]
        args += (["--sing"] if st.get("sing") else []) + (["--smooth"] if st.get("smooth") else [])
        if st.get("hifi"):
            args += ["--hifi"] + [x for k, v in st.get("tuning", {}).items() for x in ("--" + k, str(v))]
        args += [] if st.get("tone", True) else ["--no-tone"]
        args += ["--fx", st["effects"]] if st.get("effects") else []
        r = subprocess.run(args + extra, input=text.encode("utf-8"), capture_output=True,
                           creationflags=NO_WINDOW, timeout=60)
        return r

    def phonemes(self, sam, text):
        r = self._run(settings_for(sam), text or SAMPLE_TEXT, ["--phonemes"])
        return [p for p in r.stdout.decode("utf-8", "replace").splitlines() if p.strip()]

    def sample(self, sam, text, variety=False, female=False):
        """SAM reading text (or a sample line) as the game would, into
        voice_work/sam_sample.wav; variety: three different monsters of
        this speaker, one after another."""
        os.makedirs(self.work, exist_ok=True)
        ids = [101, 2023, 30307] if variety else [0]
        frames = b""
        for i, m_id in enumerate(ids):
            part = self.sample_path + ".part"
            r = self._run(settings_for(sam, m_id, female), text or SAMPLE_TEXT, ["--wav", part])
            if r.returncode or not os.path.exists(part):
                raise ValueError("SAM couldn't say that")
            with wave.open(part, "rb") as w:
                frames += w.readframes(w.getnframes())
            os.remove(part)
            if i < len(ids) - 1:
                frames += struct.pack("<h", 0) * int(22050 * 0.4)
        with wave.open(self.sample_path, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(22050)
            w.writeframes(frames)
        return self.sample_path
