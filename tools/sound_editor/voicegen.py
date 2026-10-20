"""Voice generation for the sound editor: Kokoro text-to-speech, run locally,
then an effect chain (ffmpeg filters) and the global sample rate.

  Kokoro    one take per "Generate": the line's speakable text, read by the
            voice cast for its speaker (one Kokoro voice, or a blend of
            several, at a chosen speed). Takes are kept in voice_work/takes/,
            listed in voice_work/takes.json. Kokoro runs in its own Python
            environment (voice_work/kokoro/, made by "Install Kokoro" in the
            Voice casting tab) through kokoro_worker.py, so the editor itself
            still needs nothing but Python and ffmpeg.
  Effects   a preset is a list of effects (pitch, filters, echo, reverb,
            robot...), applied in order with ffmpeg; every result is then
            resampled to the global output rate (11025 Hz by default) and
            saved as Ogg. A preview waits in voice_work/pending/ until it is
            confirmed; then it becomes the line's voice in sounds/voices/.
"""
import json
import math
import os
import re
import shutil
import subprocess
import sys
import threading
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)

KOKORO_PACKAGES = ["kokoro-onnx==0.4.7", "soundfile"]
MODEL_URL = "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/"
MODEL_FILES = {"kokoro-v1.0.int8.onnx": 92361271, "voices-v1.0.bin": 28214398}
SAMPLE_TEXT = "Hello, adventurer! Welcome to the Dungeons of Doom. Mind the floating eye."

# a Kokoro voice's first letter is its language, the second its gender
LANGS = {"a": ("en-us", "American English"), "b": ("en-gb", "British English"),
         "e": ("es", "Spanish"), "f": ("fr-fr", "French"), "h": ("hi", "Hindi"),
         "i": ("it", "Italian"), "j": ("ja", "Japanese"), "p": ("pt-br", "Brazilian Portuguese"),
         "z": ("cmn", "Mandarin")}

DEFAULT_CAST = {
    "version": 2,
    "output": {"rate": 11025, "quality": 4},
    "speakers": {},
    "presets": {
        "Plain": {"effects": [{"type": "normalize", "peak": -1}]},
        "Echoing hall": {"effects": [
            {"type": "reverb", "room": 85, "mix": 40},
            {"type": "normalize", "peak": -1}]},
        "Monster": {"effects": [
            {"type": "pitch", "semitones": -5, "formants": 0},
            {"type": "distortion", "drive": 6},
            {"type": "normalize", "peak": -1}]},
        "Ghostly": {"effects": [
            {"type": "whisper", "size": 512},
            {"type": "reverb", "room": 70, "mix": 50},
            {"type": "normalize", "peak": -1}]},
        "Radio": {"effects": [
            {"type": "highpass", "freq": 300}, {"type": "lowpass", "freq": 3400},
            {"type": "distortion", "drive": 10}, {"type": "normalize", "peak": -1}]},
        "Robot": {"effects": [
            {"type": "robot", "size": 512}, {"type": "normalize", "peak": -1}]},
    },
    "lines": {},
}


def safe_id(line_id):
    return re.sub(r"[^a-z0-9_]+", "_", line_id.lower()).strip("_")[:60]


def voice_info(name):
    lang, label = LANGS.get(name[:1], ("en-us", "Other"))
    return {"id": name, "name": name[3:].replace("_", " ").title() if "_" in name else name,
            "lang": lang, "language": label,
            "gender": {"f": "female", "m": "male"}.get(name[1:2], "")}


def voice_lang(spec):
    """The language a voice spec is read in: its first (or only) voice's."""
    first = str(spec or "").split("+")[0].split("*")[0].strip()
    return LANGS.get(first[:1], ("en-us", ""))[0]


def voice_label(spec):
    """'af_heart*0.6+bf_emma*0.4' -> 'Heart 60% + Emma 40%'"""
    parts = [p.strip().partition("*") for p in str(spec or "").split("+") if p.strip()]
    if len(parts) == 1:
        return voice_info(parts[0][0])["name"]
    total = sum(float(w or 1) for _, _, w in parts) or 1
    return " + ".join("%s %d%%" % (voice_info(n)["name"], round(100 * float(w or 1) / total)) for n, _, w in parts)


# ---------------------------------------------------------------- effects
def _p(key, label, lo, hi, step, default, unit="", kind="number", choices=None):
    d = {"key": key, "label": label, "min": lo, "max": hi, "step": step, "default": default, "unit": unit,
         "type": kind}
    if choices:
        d["choices"] = choices
    return d


EFFECTS = {
    "normalize": {"name": "Normalize", "tip": "Turn the whole line up or down so its loudest peak is at this level.",
                  "params": [_p("peak", "Peak", -24, 0, 0.5, -1, "dB")]},
    "gain": {"name": "Volume", "tip": "Louder or quieter by a fixed amount.",
             "params": [_p("db", "Gain", -24, 24, 0.5, 0, "dB")]},
    "pitch": {"name": "Pitch", "tip": "Higher or lower without changing the speed. Keeping the formants sounds "
              "like the same person singing higher or lower; shifting them sounds like a bigger or smaller creature.",
              "params": [_p("semitones", "Semitones", -12, 12, 0.5, -3, "st"),
                         _p("formants", "Keep formants", 0, 1, 1, 0, kind="bool")]},
    "tempo": {"name": "Tempo", "tip": "Faster or slower without changing the pitch.",
              "params": [_p("factor", "Speed", 0.5, 2, 0.05, 1, "×")]},
    "highpass": {"name": "High-pass filter", "tip": "Cuts the bass below this frequency (thin, small, tinny).",
                 "params": [_p("freq", "Cutoff", 20, 4000, 10, 200, "Hz")]},
    "lowpass": {"name": "Low-pass filter", "tip": "Cuts the treble above this frequency (muffled, behind a door).",
                "params": [_p("freq", "Cutoff", 200, 20000, 50, 3500, "Hz")]},
    "eq": {"name": "EQ band", "tip": "Boost or cut one band of frequencies.",
           "params": [_p("freq", "Centre", 40, 16000, 10, 1000, "Hz"), _p("q", "Width (Q)", 0.1, 10, 0.1, 1),
                      _p("db", "Gain", -24, 24, 0.5, 6, "dB")]},
    "compressor": {"name": "Compressor", "tip": "Evens out loud and quiet parts.",
                   "params": [_p("threshold", "Threshold", -40, 0, 1, -18, "dB"), _p("ratio", "Ratio", 1, 20, 0.5, 4, ":1")]},
    "echo": {"name": "Echo", "tip": "Distinct repeats of the voice.",
             "params": [_p("delay", "Delay", 20, 1500, 10, 250, "ms"), _p("decay", "Decay", 0.05, 0.95, 0.05, 0.4),
                        _p("repeats", "Repeats", 1, 8, 1, 3)]},
    "reverb": {"name": "Reverb", "tip": "A room around the voice: small rooms to great halls.",
               "params": [_p("room", "Room size", 0, 100, 1, 60, "%"), _p("mix", "Wet", 0, 100, 1, 35, "%")]},
    "chorus": {"name": "Chorus", "tip": "Several voices at once, slightly apart.",
               "params": [_p("mix", "Wet", 0, 100, 1, 50, "%"), _p("rate", "Rate", 0.1, 5, 0.1, 0.6, "Hz"),
                          _p("depth", "Depth", 0.5, 10, 0.5, 2.5, "ms")]},
    "flanger": {"name": "Flanger", "tip": "A sweeping, metallic whoosh.",
                "params": [_p("depth", "Depth", 0, 10, 0.5, 3, "ms"), _p("speed", "Speed", 0.1, 10, 0.1, 0.5, "Hz"),
                           _p("regen", "Feedback", -95, 95, 1, 40, "%")]},
    "tremolo": {"name": "Tremolo", "tip": "The volume wobbles.",
                "params": [_p("freq", "Rate", 0.5, 20, 0.5, 6, "Hz"), _p("depth", "Depth", 0, 1, 0.05, 0.5)]},
    "vibrato": {"name": "Vibrato", "tip": "The pitch wobbles.",
                "params": [_p("freq", "Rate", 0.5, 20, 0.5, 5, "Hz"), _p("depth", "Depth", 0, 1, 0.05, 0.3)]},
    "distortion": {"name": "Distortion", "tip": "Overdriven and gritty.",
                   "params": [_p("drive", "Drive", 0, 40, 1, 12, "dB")]},
    "bitcrush": {"name": "Bitcrusher", "tip": "Lo-fi digital grit: fewer bits, a lower sample rate.",
                 "params": [_p("bits", "Bits", 2, 16, 1, 8), _p("downsample", "Downsample", 1, 16, 1, 1, "×")]},
    "robot": {"name": "Robot", "tip": "A flat, buzzing machine voice. Smaller sizes buzz higher.",
              "params": [_p("size", "Size", 128, 2048, 0, 512, kind="choice", choices=[128, 256, 512, 1024, 2048])]},
    "whisper": {"name": "Whisper", "tip": "Breathy and voiceless: ghosts and secrets.",
                "params": [_p("size", "Size", 128, 2048, 0, 512, kind="choice", choices=[128, 256, 512, 1024, 2048])]},
}


def _num(fx, key):
    spec = next(p for p in EFFECTS[fx["type"]]["params"] if p["key"] == key)
    try:
        v = float(fx.get(key, spec["default"]))
    except (TypeError, ValueError):
        v = float(spec["default"])
    if not math.isfinite(v):
        v = float(spec["default"])
    return min(max(v, spec["min"]), spec["max"])


def _taps(delays, decays, gain_in=1.0, gain_out=1.0):
    return "aecho=%g:%g:%s:%s" % (gain_in, gain_out, "|".join("%g" % round(d, 1) for d in delays),
                                  "|".join("%g" % round(d, 3) for d in decays))


def effect_filter(fx):
    """One effect -> (ffmpeg filter text, seconds of tail it needs)."""
    t = fx.get("type")
    n = lambda k: _num(fx, k)  # noqa: E731
    if t == "gain":
        return "volume=%gdB" % n("db"), 0
    if t == "pitch":
        return "rubberband=pitch=%.6f:formant=%s" % (2 ** (n("semitones") / 12),
                                                     "preserved" if n("formants") else "shifted"), 0
    if t == "tempo":
        return "atempo=%g" % n("factor"), 0
    if t == "highpass":
        return "highpass=f=%g" % n("freq"), 0
    if t == "lowpass":
        return "lowpass=f=%g" % n("freq"), 0
    if t == "eq":
        return "equalizer=f=%g:t=q:w=%g:g=%g" % (n("freq"), n("q"), n("db")), 0
    if t == "compressor":
        return "acompressor=threshold=%gdB:ratio=%g:attack=5:release=80:makeup=2" % (n("threshold"), n("ratio")), 0
    if t == "echo":
        reps, delay, decay = int(n("repeats")), n("delay"), n("decay")
        tail = delay * reps / 1000 + 0.3
        return "apad=pad_dur=%g,%s" % (tail, _taps([delay * (i + 1) for i in range(reps)],
                                                   [decay ** (i + 1) for i in range(reps)], 1, 0.8)), tail
    if t == "reverb":
        # reflections spread over the room's decay time, fading by 60 dB
        # across it, then smeared by a few short prime-length echoes
        room, mix = n("room") / 100, n("mix") / 100
        rt = 0.25 + 2.75 * room
        count = 16
        delays = [11 + 1000 * rt * 0.5 * ((i + 1) / count) ** 1.6 + (i * 7919 % 13) for i in range(count)]
        decays = [mix * 0.8 * 10 ** (-3 * d / (1000 * rt)) for d in delays]
        tail = rt + 0.2
        return "apad=pad_dur=%g,%s,%s" % (
            tail, _taps(delays, decays, 1, 0.8), _taps([7, 13, 19, 29], [0.35, 0.28, 0.22, 0.16], 1, 0.7)), tail
    if t == "chorus":
        mix, rate, depth = n("mix") / 100, n("rate"), n("depth")
        return "chorus=%g:%g:45|60:%g|%g:%g|%g:%g|%g" % (1 - mix * 0.4, 0.9, mix * 0.6, mix * 0.5,
                                                         rate, rate * 1.3, depth, depth * 0.8), 0.1
    if t == "flanger":
        return "flanger=depth=%g:speed=%g:regen=%g" % (n("depth"), n("speed"), n("regen")), 0
    if t == "tremolo":
        return "tremolo=f=%g:d=%g" % (n("freq"), max(n("depth"), 0.01)), 0
    if t == "vibrato":
        return "vibrato=f=%g:d=%g" % (n("freq"), max(n("depth"), 0.01)), 0
    if t == "distortion":
        d = n("drive")
        return "volume=%gdB,asoftclip=type=tanh,volume=-3dB" % d, 0
    if t == "bitcrush":
        return "acrusher=bits=%d:samples=%d:mode=lin:aa=0" % (n("bits"), n("downsample")), 0
    if t == "robot":
        size = int(n("size"))
        return "afftfilt=real='hypot(re,im)':imag='0':win_size=%d:overlap=0.75" % size, 0
    if t == "whisper":
        size = int(n("size"))
        return ("afftfilt=real='hypot(re,im)*cos((random(0)*2-1)*2*3.14)'"
                ":imag='hypot(re,im)*sin((random(1)*2-1)*2*3.14)':win_size=%d:overlap=0.6" % size), 0
    return "", 0


def pitch_effects(semitones):
    """A speaker's pitch: the same person, higher or lower (formants kept),
    before the preset's effects."""
    try:
        st = max(-12.0, min(12.0, float(semitones or 0)))
    except (TypeError, ValueError):
        st = 0.0
    return [{"type": "pitch", "semitones": st, "formants": 1}] if abs(st) >= 0.05 else []


def migrate_cast(cast):
    """Casts from the ElevenLabs + Tenacity editor: Tenacity steps become
    effects; ElevenLabs voices are dropped (Kokoro has different ones)."""
    for preset in cast.get("presets", {}).values():
        if "effects" in preset:
            preset.pop("steps", None)
            continue
        effects = []
        for step in preset.pop("steps", []):
            name, _, rest = step.partition(":")
            args = dict(re.findall(r"(\w+)=(\S+)", rest))
            try:
                if name.strip() == "Normalize":
                    effects.append({"type": "normalize", "peak": float(args.get("PeakLevel", -1))})
                elif name.strip() == "Reverb":
                    effects.append({"type": "reverb", "room": float(args.get("RoomSize", 75)), "mix": 40})
                elif name.strip() == "Amplify":
                    effects.append({"type": "gain", "db": float(args.get("Ratio", 0))})
                elif name.strip() == "Echo":
                    effects.append({"type": "echo", "delay": 1000 * float(args.get("Delay", 0.25)),
                                    "decay": float(args.get("Decay", 0.4)), "repeats": 3})
            except ValueError:
                pass
        # Tenacity's double normalize around a reverb is one at the end here
        while len(effects) > 1 and effects[0]["type"] == "normalize" and \
                any(e["type"] == "normalize" for e in effects[1:]):
            effects.pop(0)
        preset["effects"] = effects
    for entry in list(cast.get("speakers", {}).values()) + list(cast.get("lines", {}).values()):
        for k in ("voice_id", "voice_name", "model_id", "settings"):
            entry.pop(k, None)
    # and the newer example presets
    for name, preset in DEFAULT_CAST["presets"].items():
        cast["presets"].setdefault(name, json.loads(json.dumps(preset)))
    cast["version"] = 2
    return cast


# ---------------------------------------------------------------- Kokoro
class Kokoro:
    """Kokoro's own Python environment, and the worker process that speaks."""

    def __init__(self, work):
        self.dir = os.path.join(work, "kokoro")
        self.python = os.path.join(self.dir, "venv", "Scripts", "python.exe")
        self.models = os.path.join(self.dir, "models")
        self.lock = threading.Lock()
        self.proc = None
        self.names = None
        self.setup_state = {"running": False, "step": "", "error": "", "progress": 0}

    def model_path(self, name):
        return os.path.join(self.models, name)

    def installed(self):
        return os.path.exists(self.python) and all(
            os.path.exists(self.model_path(n)) and os.path.getsize(self.model_path(n)) == size
            for n, size in MODEL_FILES.items())

    def status(self):
        return {"installed": self.installed(), "running": bool(self.proc and self.proc.poll() is None),
                "setup": dict(self.setup_state)}

    # -- one-time setup: a virtual environment with kokoro-onnx, and the model files
    def start_setup(self):
        if self.setup_state["running"]:
            return
        self.setup_state.update(running=True, step="Starting", error="", progress=0)
        threading.Thread(target=self._setup, daemon=True).start()

    def _setup(self):
        st = self.setup_state
        try:
            os.makedirs(self.models, exist_ok=True)
            if not os.path.exists(self.python):
                st["step"] = "Making a Python environment for Kokoro"
                subprocess.run([sys.executable, "-m", "venv", os.path.join(self.dir, "venv")],
                               check=True, capture_output=True, creationflags=NO_WINDOW)
            st["step"] = "Installing kokoro-onnx (a few minutes the first time)"
            r = subprocess.run([self.python, "-m", "pip", "install", "--disable-pip-version-check",
                                "--no-input", *KOKORO_PACKAGES],
                               capture_output=True, text=True, creationflags=NO_WINDOW)
            if r.returncode:
                raise RuntimeError("pip couldn't install Kokoro: " + (r.stderr or r.stdout).strip()[-600:])
            for name, size in MODEL_FILES.items():
                path = self.model_path(name)
                if os.path.exists(path) and os.path.getsize(path) == size:
                    continue
                st["step"] = "Downloading %s (%d MB)" % (name, size // 1000000)
                part = path + ".part"
                with urllib.request.urlopen(MODEL_URL + name, timeout=60) as resp, open(part, "wb") as f:
                    got = 0
                    while True:
                        chunk = resp.read(1 << 16)
                        if not chunk:
                            break
                        f.write(chunk)
                        got += len(chunk)
                        st["progress"] = round(got / size, 3)
                if os.path.getsize(part) != size:
                    os.remove(part)
                    raise RuntimeError("The download of %s was incomplete; try again" % name)
                os.replace(part, path)
            st["step"] = "Starting Kokoro"
            self.voices()
            st["step"] = "Ready"
        except (OSError, RuntimeError, subprocess.CalledProcessError) as e:
            st["error"] = str(e)
        finally:
            st["running"] = False

    # -- the worker
    def _start(self):
        if self.proc and self.proc.poll() is None:
            return
        if not self.installed():
            raise RuntimeError("Kokoro isn't installed yet: press Install Kokoro in the Voice casting tab")
        log = open(os.path.join(self.dir, "worker.log"), "w", encoding="utf-8")
        self.proc = subprocess.Popen(
            [self.python, os.path.join(HERE, "kokoro_worker.py"),
             self.model_path("kokoro-v1.0.int8.onnx"), self.model_path("voices-v1.0.bin")],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=log, text=True, encoding="utf-8",
            creationflags=NO_WINDOW, cwd=self.dir)
        log.close()
        if not self._read().get("ready"):
            raise RuntimeError("Kokoro didn't start")

    def _read(self):
        line = self.proc.stdout.readline()
        if not line:
            self.proc = None
            try:
                with open(os.path.join(self.dir, "worker.log"), encoding="utf-8", errors="replace") as f:
                    tail = f.read().strip().splitlines()[-1:]
            except OSError:
                tail = []
            raise RuntimeError("Kokoro stopped unexpectedly" + (": " + tail[0] if tail else ""))
        return json.loads(line)

    def call(self, req):
        with self.lock:
            self._start()
            try:
                self.proc.stdin.write(json.dumps(req) + "\n")
                self.proc.stdin.flush()
            except OSError:
                self.proc = None
                raise RuntimeError("Lost contact with Kokoro; try again")
            reply = self._read()
        if not reply.get("ok"):
            raise RuntimeError("Kokoro: " + reply.get("error", "failed"))
        return reply

    def voices(self):
        if self.names is None:
            self.names = self.call({"cmd": "voices"})["voices"]
        return self.names

    def say(self, text, voice, speed, lang, out, delivery="", delivery_mix=0.0):
        return self.call({"cmd": "say", "text": text, "voice": voice, "speed": speed, "lang": lang, "out": out,
                          "delivery": delivery, "delivery_mix": delivery_mix})


# ---------------------------------------------------------------- jobs
class VoiceGen:
    def __init__(self, root, mod, sounds, catalog, load_config, save_config, speakable):
        self.root, self.mod, self.sounds = root, mod, sounds
        self.work = os.path.join(root, "voice_work")
        self.takes_path = os.path.join(self.work, "takes.json")
        self.cast_path = os.path.join(mod, "voice_cast.json")
        self.catalog = catalog              # () -> {line id: entry}
        self.load_config, self.save_config = load_config, save_config
        self.speakable = speakable
        self.kokoro = Kokoro(self.work)
        self.lock = threading.Lock()          # jobs and takes.json
        self.render_lock = threading.RLock()  # one render at a time (shared temp files)
        self.jobs = []
        self.next_job = 1
        self.wake = threading.Event()
        self.stop_reason = ""
        threading.Thread(target=self._worker, daemon=True).start()

    # -- files
    def load_cast(self):
        try:
            with open(self.cast_path, encoding="utf-8") as f:
                cast = json.load(f)
        except (OSError, ValueError):
            cast = json.loads(json.dumps(DEFAULT_CAST))
        for k, v in DEFAULT_CAST.items():
            cast.setdefault(k, json.loads(json.dumps(v)))
        if cast.get("version", 1) < 2:
            migrate_cast(cast)
        return cast

    def save_cast(self, cast):
        tmp = self.cast_path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(cast, f, indent=1, ensure_ascii=False)
        os.replace(tmp, self.cast_path)

    def load_takes(self):
        try:
            with open(self.takes_path, encoding="utf-8") as f:
                return json.load(f)
        except (OSError, ValueError):
            return {}

    def _save_takes(self, takes):
        os.makedirs(self.work, exist_ok=True)
        tmp = self.takes_path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(takes, f, indent=1)
        os.replace(tmp, self.takes_path)

    def set_take(self, line_id, index):
        with self.lock:
            takes = self.load_takes()
            t = takes.get(line_id)
            if not t or not 0 <= index < len(t["takes"]):
                raise ValueError("no such take")
            t["current"] = index
            self._save_takes(takes)

    def take_path(self, rel):
        path = os.path.normpath(os.path.join(self.work, "takes", rel))
        if not path.startswith(os.path.join(self.work, "takes") + os.sep):
            return None
        return path

    # -- what a line will be read as: the line's own choices, else its speaker's
    NO_EFFECTS = "__none__"

    def line_plan(self, line_id, cast=None):
        cast = cast or self.load_cast()
        entry = self.catalog().get(line_id)
        if not entry:
            raise ValueError("unknown line " + line_id)
        ln = cast["lines"].get(line_id, {})
        speaker = ln.get("cast") or entry["speaker"]
        sc = cast["speakers"].get(speaker, {})
        voice = ln.get("voice") or sc.get("voice") or ""
        speed = float(ln.get("speed") or sc.get("speed") or 1.0)
        lang = (ln.get("lang") if ln.get("voice") else None) or sc.get("lang") or voice_lang(voice)
        preset = ln["preset"] if "preset" in ln else sc.get("preset", "")
        # delivery: another voice's manner (pitch level, pace, intonation);
        # a line can choose its own, or none
        delivery, mix = sc.get("delivery") or "", float(sc.get("delivery_mix") or 0.7)
        if "delivery" in ln:
            delivery = "" if ln["delivery"] == self.NO_EFFECTS else ln["delivery"]
            mix = float(ln.get("delivery_mix") or mix)
        if preset == self.NO_EFFECTS:
            preset = ""
        return {"entry": entry, "speaker": speaker, "voice": voice, "voice_name": voice_label(voice) if voice else "",
                "speed": speed, "lang": lang, "preset": preset,
                "delivery": delivery, "delivery_mix": mix if delivery else 0.0,
                "pitch": float(ln.get("pitch", sc.get("pitch", 0)) or 0),
                "text": ln.get("spoken") or self.speakable(entry)[0]}

    def pending_path(self, line_id):
        return os.path.join(self.work, "pending", safe_id(line_id) + ".ogg")

    # -- queue
    def enqueue(self, items):
        added = []
        with self.lock:
            self.stop_reason = ""
            for it in items:
                job = {"job": self.next_job, "line": it["line"], "action": it["action"],
                       "status": "queued", "message": "", "result": None}
                self.next_job += 1
                self.jobs.append(job)
                added.append(job["job"])
        self.wake.set()
        return added

    def busy(self):
        with self.lock:
            return any(j["status"] in ("queued", "running") for j in self.jobs)

    def cancel(self):
        with self.lock:
            for j in self.jobs:
                if j["status"] == "queued":
                    j["status"], j["message"] = "cancelled", "Cancelled"

    def state(self, since=0):
        with self.lock:
            jobs = [dict(j) for j in self.jobs if j["job"] > since or j["status"] in ("queued", "running")]
            # keep the list short once things are finished
            if len(self.jobs) > 400:
                self.jobs = [j for j in self.jobs if j["status"] in ("queued", "running")] + \
                    [j for j in self.jobs if j["status"] not in ("queued", "running")][-200:]
            return {"jobs": jobs, "stopped": self.stop_reason}

    def _worker(self):
        while True:
            self.wake.wait(1.0)
            self.wake.clear()
            while True:
                with self.lock:
                    job = next((j for j in self.jobs if j["status"] == "queued"), None)
                    if job:
                        job["status"] = "running"
                if not job:
                    break
                try:
                    job["result"] = self.run(job["line"], job["action"])
                    job["status"], job["message"] = "done", ""
                except (RuntimeError, ValueError, OSError, subprocess.CalledProcessError) as e:
                    job["status"], job["message"] = "error", str(e)
                    if isinstance(e, RuntimeError) and "Kokoro isn't installed" in str(e):
                        self.stop_reason = str(e)
                        self.cancel()

    # -- the work itself
    def run(self, line_id, action):
        """generate: a new Kokoro take, then a preview of it;
        process: a new preview of the current take (e.g. another effect).
        Previews wait for confirm() before the game gets them."""
        cast = self.load_cast()
        plan = self.line_plan(line_id, cast)
        if action == "generate":
            if not plan["voice"]:
                raise ValueError('Choose a voice for this line (or for "%s" in Voice casting)' % plan["speaker"])
            text = plan["text"]
            if not re.search(r"[^\W\d_]", text):
                raise ValueError("There are no words to read: this line is only placeholders. "
                                 "Write what should be said in its Spoken text first.")
            sid = safe_id(line_id)
            folder = os.path.join(self.work, "takes", sid)
            os.makedirs(folder, exist_ok=True)
            fname = time.strftime("%Y%m%d-%H%M%S") + ".wav"
            self.kokoro.say(text, plan["voice"], plan["speed"], plan["lang"], os.path.join(folder, fname),
                            plan["delivery"], plan["delivery_mix"])
            with self.lock:
                takes = self.load_takes()
                t = takes.setdefault(line_id, {"takes": [], "current": 0})
                t["takes"].append({"file": sid + "/" + fname, "voice": plan["voice_name"], "voice_spec": plan["voice"],
                                   "speed": plan["speed"], "delivery": plan["delivery"],
                                   "delivery_mix": plan["delivery_mix"], "text": text, "chars": len(text),
                                   "time": int(time.time())})
                t["current"] = len(t["takes"]) - 1
                self._save_takes(takes)
        return self.make_preview(line_id, cast, plan)

    def make_preview(self, line_id, cast, plan):
        t = self.load_takes().get(line_id)
        if not t or not t["takes"]:
            raise ValueError("This line has no generated take yet")
        index = t.get("current", 0)
        take = t["takes"][index]
        preset = cast["presets"].get(plan["preset"] or "", {})
        dst = self.pending_path(line_id)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        self.render(self.take_path(take["file"]), pitch_effects(plan["pitch"]) + preset.get("effects", []),
                    cast.get("output", {}), dst)
        pending = {"take": index, "preset": plan["preset"], "voice": take["voice"], "pitch": plan["pitch"],
                   "url": "/pending/%s.ogg?v=%d" % (safe_id(line_id), int(time.time() * 1000)),
                   "rate": int(cast.get("output", {}).get("rate") or 11025), "time": int(time.time())}
        with self.lock:
            takes = self.load_takes()
            takes[line_id]["pending"] = pending
            self._save_takes(takes)
        return {"pending": pending}

    def confirm(self, line_id):
        """The previewed audio becomes the line's voice in the game."""
        src = self.pending_path(line_id)
        with self.lock:
            takes = self.load_takes()
            t = takes.get(line_id)
            if not t or "pending" not in t or not os.path.exists(src):
                raise ValueError("There is no preview waiting for this line")
            # Luanti can't swap a sound it already sent to the game, so every
            # confirmed voice gets a new name (the old file is removed)
            sound = "voice_%s_%s" % (safe_id(line_id), format(int(time.time() * 10) % 36 ** 5, "x"))
            os.makedirs(os.path.join(self.sounds, "voices"), exist_ok=True)
            shutil.move(src, os.path.join(self.sounds, "voices", sound + ".ogg"))
            t["confirmed"] = dict(t.pop("pending"), sound=sound)
            self._save_takes(takes)
        cfg = self.load_config()
        old = cfg.setdefault("voices", {}).get(line_id, {})
        cfg["voices"][line_id] = {"sound": sound, "volume": old.get("volume", 100)}
        self.save_config(cfg)
        self._drop_old(old.get("sound"), sound)
        return {"sound": sound}

    def discard(self, line_id):
        with self.lock:
            takes = self.load_takes()
            if line_id in takes:
                takes[line_id].pop("pending", None)
                self._save_takes(takes)
        if os.path.exists(self.pending_path(line_id)):
            os.remove(self.pending_path(line_id))

    def render(self, src, effects, out, dst):
        """src audio -> the effects, in order -> the output rate -> Ogg at dst"""
        with self.render_lock:
            self._render(src, effects, out, dst)

    @staticmethod
    def _ffmpeg():
        ffmpeg = shutil.which("ffmpeg")
        if not ffmpeg:
            raise RuntimeError("ffmpeg was not found on PATH")
        return ffmpeg

    def _peak(self, path):
        r = subprocess.run([self._ffmpeg(), "-hide_banner", "-nostats", "-i", path, "-af", "volumedetect",
                            "-f", "null", "-"], capture_output=True, text=True, creationflags=NO_WINDOW)
        m = re.search(r"max_volume:\s*(-?[\d.]+|-inf) dB", r.stderr)
        return float(m.group(1)) if m and m.group(1) != "-inf" else None

    def _render(self, src, effects, out, dst):
        ffmpeg = self._ffmpeg()
        tmp = os.path.join(self.work, "tmp")
        os.makedirs(tmp, exist_ok=True)
        files = [os.path.join(tmp, "a.wav"), os.path.join(tmp, "b.wav")]
        cur = 0

        def run(args):
            r = subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-y", *args],
                               capture_output=True, text=True, creationflags=NO_WINDOW)
            if r.returncode:
                raise RuntimeError("ffmpeg: " + (r.stderr.strip().splitlines() or ["failed"])[-1])

        # 32-bit float in between, so nothing clips until the very end
        run(["-i", src, "-ac", "1", "-ar", "44100", "-c:a", "pcm_f32le", files[cur]])
        chain, padded = [], False

        def flush():
            nonlocal cur, chain
            if chain:
                run(["-i", files[cur], "-af", ",".join(chain), "-ac", "1", "-ar", "44100",
                     "-c:a", "pcm_f32le", files[1 - cur]])
                cur, chain = 1 - cur, []

        for fx in effects or []:
            if fx.get("type") not in EFFECTS or fx.get("off"):
                continue
            if fx["type"] == "normalize":
                flush()
                peak = self._peak(files[cur])
                if peak is not None:
                    chain.append("volume=%gdB" % (_num(fx, "peak") - peak))
                continue
            text, tail = effect_filter(fx)
            if text:
                chain.append(text)
                padded = padded or tail > 0
        if padded:
            # echo and reverb pad the end for their tails: trim what stayed silent
            chain.append("areverse,silenceremove=start_periods=1:start_threshold=-60dB:start_silence=0.08,areverse")
        flush()
        # never clip: anything over full scale comes down to -1 dB
        peak = self._peak(files[cur])
        final = ["volume=%gdB" % (-1 - peak)] if peak is not None and peak > -0.05 else []
        rate = int(out.get("rate") or 11025)
        run(["-i", files[cur], *(["-af", ",".join(final)] if final else []), "-ac", "1", "-ar", str(rate),
             "-c:a", "libvorbis", "-q:a", str(out.get("quality", 4)), dst])

    def _drop_old(self, old, new):
        if not old or old == new or not old.startswith("voice_"):
            return
        cfg = self.load_config()
        if any(old in (h.get("sounds") or []) for h in cfg.get("hooks", {}).values()):
            return
        if any(v.get("sound") == old for v in cfg.get("voices", {}).values()):
            return
        path = os.path.join(self.sounds, "voices", old + ".ogg")
        if os.path.exists(path):
            os.remove(path)

    def preview(self, src, effects, out):
        """Process src with effects into voice_work/preview.ogg (for listening)."""
        dst = os.path.join(self.work, "preview.ogg")
        self.render(src, effects, out, dst)
        return dst

    def sample(self, voice, speed, lang, text, effects, out, pitch=0.0, delivery="", delivery_mix=0.0):
        """A voice reading a short sample (with its pitch and delivery),
        through effects, at the output rate: voice_work/sample.ogg."""
        if not voice:
            raise ValueError("Choose a voice first")
        with self.render_lock:
            wav = os.path.join(self.work, "tmp", "sample.wav")
            os.makedirs(os.path.dirname(wav), exist_ok=True)
            self.kokoro.say(text or SAMPLE_TEXT, voice, float(speed or 1), lang or voice_lang(voice), wav,
                            delivery, float(delivery_mix or 0) if delivery else 0.0)
            dst = os.path.join(self.work, "sample.ogg")
            self._render(wav, pitch_effects(pitch) + list(effects or []), out, dst)
        return dst
