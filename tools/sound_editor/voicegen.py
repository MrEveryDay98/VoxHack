"""Voice generation for the sound editor: ElevenLabs text-to-speech, then
Tenacity for effects and the final sample rate.

  ElevenLabs   one take per "Generate": the line's speakable text, read by
               the voice cast for its speaker. Takes are kept (they cost
               credits) in voice_work/takes/, listed in voice_work/takes.json.
  Tenacity     driven through its scripting pipe (mod-script-pipe). A take
               is imported, the chosen preset (a list of Tenacity macro
               commands) is applied, the project rate is set (11025 Hz by
               default) and it is exported; ffmpeg makes an Ogg preview
               (voice_work/pending/). Once confirmed, the preview becomes the
               line's voice in sounds/voices/.

The API key is kept out of the project, encrypted for the current Windows
user (DPAPI), in %APPDATA%/NetHackVoxel/elevenlabs.key. The environment
variable ELEVENLABS_API_KEY is used when no key was saved.
"""
import contextlib
import ctypes
import json
import os
import re
import shutil
import subprocess
import threading
import time
import urllib.error
import urllib.request

API = os.environ.get("NHV_ELEVENLABS_URL", "https://api.elevenlabs.io")
KEY_DIR = os.path.join(os.environ.get("APPDATA", os.path.expanduser("~")), "NetHackVoxel")
KEY_FILE = os.path.join(KEY_DIR, "elevenlabs.key")
TENACITY_MACROS = os.path.join(os.environ.get("APPDATA", ""), "tenacity", "Macros")
TO_PIPE = r"\\.\pipe\ToSrvPipe"
FROM_PIPE = r"\\.\pipe\FromSrvPipe"

DEFAULT_CAST = {
    "version": 1,
    "output": {"rate": 11025, "quality": 4},
    "speakers": {},
    "presets": {
        "Plain": {"steps": [
            "Normalize: PeakLevel=-1 ApplyGain=1 RemoveDcOffset=1 StereoIndependent=0"]},
        "Echoing hall": {"steps": [
            "Normalize: PeakLevel=-3 ApplyGain=1 RemoveDcOffset=1 StereoIndependent=0",
            "Reverb: RoomSize=85 Reverberance=60 WetGain=-4 DryGain=-1",
            "Normalize: PeakLevel=-1 ApplyGain=1 RemoveDcOffset=0 StereoIndependent=0"]},
    },
    "lines": {},
}


def safe_id(line_id):
    return re.sub(r"[^a-z0-9_]+", "_", line_id.lower()).strip("_")[:60]


# ---------------------------------------------------------------- API key
class _Blob(ctypes.Structure):
    _fields_ = [("cbData", ctypes.c_uint32), ("pbData", ctypes.POINTER(ctypes.c_char))]


def _dpapi(data, protect):
    buf = ctypes.create_string_buffer(data, len(data))
    blob_in = _Blob(len(data), ctypes.cast(buf, ctypes.POINTER(ctypes.c_char)))
    blob_out = _Blob()
    crypt32 = ctypes.windll.crypt32
    fn = crypt32.CryptProtectData if protect else crypt32.CryptUnprotectData
    if not fn(ctypes.byref(blob_in), None, None, None, None, 0, ctypes.byref(blob_out)):
        raise OSError("Windows could not %s the key" % ("encrypt" if protect else "decrypt"))
    try:
        return ctypes.string_at(blob_out.pbData, blob_out.cbData)
    finally:
        ctypes.windll.kernel32.LocalFree(ctypes.cast(blob_out.pbData, ctypes.c_void_p))


def get_key():
    return key_info()[0]


def key_info():
    """(key, where it came from: "saved" | "environment" | "")"""
    try:
        with open(KEY_FILE, "rb") as f:
            return _dpapi(f.read(), False).decode("utf-8"), "saved"
    except OSError:
        key = os.environ.get("ELEVENLABS_API_KEY", "")
        return key, "environment" if key else ""


def set_key(key):
    key = key.strip()
    if not key:
        if os.path.exists(KEY_FILE):
            os.remove(KEY_FILE)
        return
    os.makedirs(KEY_DIR, exist_ok=True)
    with open(KEY_FILE, "wb") as f:
        f.write(_dpapi(key.encode("utf-8"), True))


class ApiError(Exception):
    def __init__(self, status, message, code=""):
        super().__init__(message)
        self.status, self.code = status, code


def eleven(method, path, body=None, accept="application/json", timeout=120):
    key = get_key()
    if not key:
        raise ApiError(401, "No ElevenLabs API key saved yet", "no_key")
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method, headers={
        "xi-api-key": key, "Accept": accept, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read()
            return raw if accept != "application/json" else json.loads(raw.decode("utf-8"))
    except urllib.error.HTTPError as e:
        msg, code = e.reason, ""
        try:
            detail = json.loads(e.read().decode("utf-8")).get("detail")
            if isinstance(detail, dict):
                msg, code = detail.get("message", msg), detail.get("status", "")
            elif isinstance(detail, str):
                msg = detail
            elif isinstance(detail, list) and detail:
                msg = "; ".join(str(d.get("msg", d)) for d in detail)
        except (ValueError, AttributeError):
            pass
        raise ApiError(e.code, "ElevenLabs: %s" % msg, code)
    except urllib.error.URLError as e:
        raise ApiError(0, "Could not reach ElevenLabs: %s" % e.reason, "network")


def tts(voice_id, text, model_id, settings):
    vs = {k: settings[k] for k in ("stability", "similarity_boost", "style", "use_speaker_boost", "speed")
          if k in settings}
    return eleven("POST", "/v1/text-to-speech/%s?output_format=mp3_44100_128" % voice_id,
                  {"text": text, "model_id": model_id, "voice_settings": vs}, accept="audio/mpeg")


# ---------------------------------------------------------------- Tenacity
def fix_json_escapes(text):
    """Double any backslash that doesn't start a valid JSON escape."""
    def one(m):
        return m.group(0) if m.group(1) in '"\\/bfnrtu' else "\\\\" + m.group(1)
    return re.sub(r"\\(.)", one, text, flags=re.S)


class Tenacity:
    """Talks to Tenacity through mod-script-pipe.

    Tenacity serves one connected program at a time, so the pipe is only
    held for one piece of work (a session) and then let go."""

    def __init__(self):
        self.lock = threading.RLock()
        self.to = self.frm = None
        self.depth = 0
        self.commands = None

    def _open(self):
        deadline = time.time() + 6
        while True:
            try:
                self.to = open(TO_PIPE, "w", encoding="utf-8")
                self.frm = open(FROM_PIPE, "r", encoding="utf-8")
                return
            except OSError as e:
                self._close()
                # "all pipe instances are busy": someone else is talking to it
                if getattr(e, "winerror", None) == 231:
                    if time.time() < deadline:
                        time.sleep(0.3)
                        continue
                    raise RuntimeError(
                        "Tenacity is busy with another program (an older copy of this editor "
                        "may still be running: close its window or tab and try again).")
                raise RuntimeError(
                    "Tenacity isn't reachable. Start Tenacity, and make sure mod-script-pipe is "
                    "Enabled in Edit > Preferences > Modules (then restart Tenacity once).")

    def _close(self):
        for f in (self.to, self.frm):
            try:
                if f:
                    f.close()
            except OSError:
                pass
        self.to = self.frm = None

    @contextlib.contextmanager
    def session(self):
        with self.lock:
            if self.depth == 0:
                self._open()
            self.depth += 1
            try:
                yield self
            finally:
                self.depth -= 1
                if self.depth == 0:
                    self._close()

    def connected(self):
        try:
            with self.session():
                return True
        except RuntimeError:
            return False

    def cmd(self, line):
        """Run one scripting command; returns its output, raises on failure."""
        with self.session():
            try:
                self.to.write(line + "\r\n\0")
                self.to.flush()
                out = []
                while True:
                    s = self.frm.readline()
                    if s == "":
                        raise OSError("pipe closed")
                    if s == "\n" and out and out[-1].startswith("BatchCommand finished"):
                        break
                    out.append(s.rstrip("\n"))
            except OSError:
                self._close()
                self.depth = 0
                raise RuntimeError("Lost the connection to Tenacity (was it closed?)")
        status = out[-1] if out else ""
        body = "\n".join(out[:-1])
        if not status.endswith("OK"):
            raise RuntimeError("Tenacity: '%s' failed. %s" % (line.split(":")[0], body.strip()[:300]))
        return body

    def get_commands(self):
        if self.commands is None:
            text = self.cmd("GetInfo: Type=Commands Format=JSON")
            text = text[text.index("["):]
            # Tenacity doesn't escape backslashes (e.g. in Windows paths)
            text = fix_json_escapes(text)
            self.commands = json.loads(text, strict=False)
        return self.commands

    def process(self, src_wav, steps, rate, dst_wav):
        q = lambda p: '"%s"' % p.replace("\\", "/")
        with self.session():
            self.cmd("SelectAll:")
            self.cmd("RemoveTracks:")
            self.cmd("Import2: Filename=%s" % q(src_wav))
            for step in steps:
                step = step.strip()
                if step and not step.startswith("#"):
                    self.cmd("SelectAll:")
                    self.cmd(step if ":" in step else step + ":")
            self.cmd("SetProject: Rate=%d" % int(rate))
            self.cmd("SelectAll:")
            self.cmd("Export2: Filename=%s NumChannels=1" % q(dst_wav))
            self.cmd("SelectAll:")
            self.cmd("RemoveTracks:")


def list_macros():
    out = {}
    if os.path.isdir(TENACITY_MACROS):
        for f in sorted(os.listdir(TENACITY_MACROS)):
            if f.lower().endswith(".txt"):
                with open(os.path.join(TENACITY_MACROS, f), encoding="utf-8", errors="replace") as fh:
                    out[f[:-4]] = [s.rstrip("\r\n") for s in fh if s.strip()]
    return out


def save_macro(name, steps):
    name = re.sub(r'[\\/:*?"<>|]+', "_", name).strip() or "NetHack Voxel preset"
    os.makedirs(TENACITY_MACROS, exist_ok=True)
    with open(os.path.join(TENACITY_MACROS, name + ".txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(s for s in steps if s.strip()) + "\n")
    return name


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
        self.tenacity = Tenacity()
        self.lock = threading.Lock()          # jobs and takes.json
        self.render_lock = threading.RLock()  # one Tenacity render at a time
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
        if ln.get("voice_id"):
            voice_id, voice_name = ln["voice_id"], ln.get("voice_name", ln["voice_id"])
            model = ln.get("model_id") or sc.get("model_id")
        else:
            voice_id, voice_name = sc.get("voice_id"), sc.get("voice_name", sc.get("voice_id"))
            model = sc.get("model_id")
        preset = ln["preset"] if "preset" in ln else sc.get("preset", "")
        if preset == self.NO_EFFECTS:
            preset = ""
        return {"entry": entry, "speaker": speaker, "voice_id": voice_id, "voice_name": voice_name,
                "model_id": model or "eleven_multilingual_v2", "settings": sc.get("settings", {}),
                "preset": preset, "text": ln.get("spoken") or self.speakable(entry)[0]}

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
                except ApiError as e:
                    job["status"], job["message"] = "error", str(e)
                    if e.code in ("no_key", "quota_exceeded") or e.status in (401, 402):
                        self.stop_reason = str(e)
                        self.cancel()
                except (RuntimeError, ValueError, OSError, subprocess.CalledProcessError) as e:
                    job["status"], job["message"] = "error", str(e)
                    if isinstance(e, RuntimeError) and "Tenacity" in str(e) and "reach" in str(e):
                        self.stop_reason = str(e)
                        self.cancel()

    # -- the work itself
    def run(self, line_id, action):
        """generate: a new ElevenLabs take, then a preview of it;
        process: a new preview of the current take (e.g. another effect).
        Previews wait for confirm() before the game gets them."""
        cast = self.load_cast()
        plan = self.line_plan(line_id, cast)
        if action == "generate":
            if not plan["voice_id"]:
                raise ValueError('Choose a voice for this line (or for "%s" in Voice casting)' % plan["speaker"])
            text = plan["text"]
            if not re.search(r"[^\W\d_]", text):
                raise ValueError("There are no words to read: this line is only placeholders. "
                                 "Write what should be said in its Spoken text first.")
            audio = None
            for attempt in range(4):
                try:
                    audio = tts(plan["voice_id"], text, plan["model_id"], plan["settings"])
                    break
                except ApiError as e:
                    if e.status != 429 or attempt == 3:
                        raise
                    time.sleep(2 + attempt * 3)  # busy: wait and retry
            sid = safe_id(line_id)
            folder = os.path.join(self.work, "takes", sid)
            os.makedirs(folder, exist_ok=True)
            fname = time.strftime("%Y%m%d-%H%M%S") + ".mp3"
            with open(os.path.join(folder, fname), "wb") as f:
                f.write(audio)
            with self.lock:
                takes = self.load_takes()
                t = takes.setdefault(line_id, {"takes": [], "current": 0})
                t["takes"].append({"file": sid + "/" + fname, "voice": plan["voice_name"],
                                   "voice_id": plan["voice_id"], "model": plan["model_id"], "text": text,
                                   "chars": len(text), "time": int(time.time())})
                t["current"] = len(t["takes"]) - 1
                self._save_takes(takes)
        return self.make_preview(line_id, cast, plan)

    def make_preview(self, line_id, cast, plan):
        t = self.load_takes().get(line_id)
        if not t or not t["takes"]:
            raise ValueError("This line has no generated take yet")
        index = t.get("current", 0)
        take = t["takes"][index]
        preset = cast["presets"].get(plan["preset"] or "", {"steps": []})
        dst = self.pending_path(line_id)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        self.render(self.take_path(take["file"]), preset.get("steps", []), cast.get("output", {}), dst)
        pending = {"take": index, "preset": plan["preset"], "voice": take["voice"],
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

    def render(self, src, steps, out, dst):
        """src audio -> Tenacity (preset steps, then the output rate) -> Ogg at dst"""
        with self.render_lock:
            self._render(src, steps, out, dst)

    def _render(self, src, steps, out, dst):
        ffmpeg = shutil.which("ffmpeg")
        if not ffmpeg:
            raise RuntimeError("ffmpeg was not found on PATH")
        tmp = os.path.join(self.work, "tmp")
        os.makedirs(tmp, exist_ok=True)
        wav_in = os.path.join(tmp, "in.wav")
        wav_out = os.path.join(tmp, "out.wav")
        for p in (wav_in, wav_out):
            if os.path.exists(p):
                os.remove(p)
        subprocess.run([ffmpeg, "-loglevel", "error", "-y", "-i", src, "-ac", "1", "-ar", "44100",
                        wav_in], check=True)
        rate = int(out.get("rate") or 11025)
        self.tenacity.process(wav_in, steps, rate, wav_out)
        for _ in range(50):  # the export can land a moment after the reply
            if os.path.exists(wav_out) and os.path.getsize(wav_out) > 44:
                break
            time.sleep(0.1)
        else:
            raise RuntimeError("Tenacity did not export the file")
        subprocess.run([ffmpeg, "-loglevel", "error", "-y", "-i", wav_out, "-ac", "1",
                        "-ar", str(rate), "-c:a", "libvorbis", "-q:a", str(out.get("quality", 4)),
                        dst], check=True)

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

    def preview(self, src, steps, out):
        """Process src with steps into voice_work/preview.ogg (for listening)."""
        dst = os.path.join(self.work, "preview.ogg")
        self.render(src, steps, out, dst)
        return dst
