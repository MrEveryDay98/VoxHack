"""Local server for the NetHack Voxel sound & voice editor.

Serves the editor page and reads/writes the game's sound data in
game/nethackvoxel/mods/nhv_sounds:
  config.json        hook -> sounds, music, voices, master volumes
  voice_cast.json    voice casting: ElevenLabs voice per speaker, effect
                     presets, output rate, spoken-text overrides
  sounds/**.ogg      sound effects, music and voice lines (folders allowed;
                     names must be unique across folders, as in Luanti)
  catalog/*.json     hooks.json (every hook) and dialogue.json (every line)

Voice generation (ElevenLabs + Tenacity) lives in voicegen.py.

Shuts itself down when the editor page is closed (and no voices are still
being generated). Only listens on 127.0.0.1, and only answers API calls made by its own page
(other websites can't use it to spend ElevenLabs credits). Uploaded audio is
converted to Ogg Vorbis with ffmpeg. The game picks up changes to
config.json within a couple of seconds.

usage: python server.py [port]
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, unquote, urlparse

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import speakable  # noqa: E402
import voicegen  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
MOD = os.path.join(ROOT, "game", "nethackvoxel", "mods", "nhv_sounds")
SOUNDS = os.path.join(MOD, "sounds")
CONFIG = os.path.join(MOD, "config.json")
CATALOG = os.path.join(MOD, "catalog")
STATIC = {"/": ("index.html", "text/html"), "/app.js": ("app.js", "text/javascript"),
          "/voices.js": ("voices.js", "text/javascript"), "/style.css": ("style.css", "text/css")}
NAME_RE = re.compile(r"^[a-z0-9_]{1,80}$")
FOLDER_PART = re.compile(r"^[a-z0-9_][a-z0-9_ .-]{0,40}$")
PORT = 8765
config_lock = threading.Lock()

# the page pings every 30 s and says goodbye when it closes
SILENCE_LIMIT = 150   # no contact for this long: the browser is gone
STARTUP_LIMIT = 300   # time allowed for the browser to open the page at first
BYE_GRACE = 5         # after a goodbye, wait this long (a reload comes back)
last_seen = time.time() + (STARTUP_LIMIT - SILENCE_LIMIT)
bye_at = None


def seen():
    global last_seen, bye_at
    last_seen = time.time()
    bye_at = None


def load_json(path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def write_json(path, data, backup=False):
    if backup and os.path.exists(path):
        shutil.copyfile(path, path + ".bak")
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1, ensure_ascii=False)
    os.replace(tmp, path)


def load_config():
    return load_json(CONFIG, {"version": 1, "hooks": {}, "voices": {}})


def save_config(cfg):
    with config_lock:
        write_json(CONFIG, cfg, backup=True)


_dialogue = None


def dialogue():
    global _dialogue
    if _dialogue is None:
        entries = load_json(os.path.join(CATALOG, "dialogue.json"), {}).get("entries", [])
        for e in entries:
            e["spoken"], e["varies"] = speakable.speakable(e)
        _dialogue = entries
    return _dialogue


def dialogue_by_id():
    return {e["id"]: e for e in dialogue()}


# ---------------------------------------------------------------- library
def clean_folder(folder):
    """'Monsters/Dragons' -> 'monsters/dragons' (or raises ValueError)"""
    parts = [p.strip().lower() for p in re.split(r"[\\/]+", folder or "") if p.strip()]
    for p in parts:
        if not FOLDER_PART.match(p) or p in (".", ".."):
            raise ValueError("bad folder name: " + p)
    return "/".join(parts)


def sound_index():
    """{name: folder} for every .ogg under sounds/"""
    out = {}
    for dirpath, dirs, files in os.walk(SOUNDS):
        dirs.sort()
        rel = os.path.relpath(dirpath, SOUNDS).replace("\\", "/")
        rel = "" if rel == "." else rel
        for f in sorted(files):
            if f.endswith(".ogg"):
                out.setdefault(f[:-4], rel)
    return out


def sound_path(name, folder=None):
    if folder is None:
        folder = sound_index().get(name)
        if folder is None:
            return None
    return os.path.join(SOUNDS, *(folder.split("/") if folder else []), name + ".ogg")


def list_sounds():
    out = []
    for name, folder in sorted(sound_index().items()):
        out.append({"name": name, "folder": folder, "size": os.path.getsize(sound_path(name, folder))})
    return out


def list_folders():
    out = []
    for dirpath, dirs, _ in os.walk(SOUNDS):
        rel = os.path.relpath(dirpath, SOUNDS).replace("\\", "/")
        if rel != ".":
            out.append(rel)
    return sorted(out)


def unique_name(name, index):
    if name not in index:
        return name
    n = 2
    while "%s_%d" % (name[:76], n) in index:
        n += 1
    return "%s_%d" % (name[:76], n)


def convert(src, dst):
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise RuntimeError("ffmpeg was not found on PATH")
    subprocess.run([ffmpeg, "-loglevel", "error", "-y", "-i", src, "-vn",
                    "-c:a", "libvorbis", "-q:a", "5", dst], check=True)


# ---------------------------------------------------------------- voice gen
VG = voicegen.VoiceGen(ROOT, MOD, SOUNDS, dialogue_by_id, load_config, save_config,
                       speakable.speakable)


class Server(ThreadingHTTPServer):
    daemon_threads = True

    def handle_error(self, request, client_address):
        # a page closed or reloaded mid-request: nothing to report
        if not isinstance(sys.exc_info()[1], (ConnectionError, TimeoutError)):
            super().handle_error(request, client_address)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        if os.environ.get("NHV_EDITOR_LOG"):
            sys.stderr.write("%s %s\n" % (time.strftime("%H:%M:%S"), fmt % args))

    def send(self, code, body, ctype="application/json"):
        if isinstance(body, (dict, list)):
            body = json.dumps(body).encode("utf-8")
        elif isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def send_file(self, path, ctype):
        if not path or not os.path.isfile(path):
            return self.send(404, {"error": "not found"})
        with open(path, "rb") as f:
            return self.send(200, f.read(), ctype)

    def allowed(self):
        """Only this editor's own page may use the API."""
        host = self.headers.get("Host", "")
        if host not in ("127.0.0.1:%d" % PORT, "localhost:%d" % PORT):
            return False
        origin = self.headers.get("Origin")
        if origin and origin not in ("http://127.0.0.1:%d" % PORT, "http://localhost:%d" % PORT):
            return False
        if self.headers.get("X-NHV") != "1":
            return False
        seen()
        return True

    def body_json(self):
        n = int(self.headers.get("Content-Length", "0"))
        if n > 20 * 1024 * 1024:
            raise ValueError("request too large")
        data = json.loads(self.rfile.read(n).decode("utf-8") or "null")
        return data

    def read_body(self):
        n = int(self.headers.get("Content-Length", "0"))
        if n > 200 * 1024 * 1024:
            raise ValueError("file too large")
        return self.rfile.read(n)

    # -------------------------------------------------------------- GET
    def do_GET(self):
        url = urlparse(self.path)
        q = parse_qs(url.query)
        if url.path in STATIC:
            fname, ctype = STATIC[url.path]
            return self.send_file(os.path.join(HERE, fname), ctype + "; charset=utf-8")
        m = re.match(r"^/sounds/([a-z0-9_]+)\.ogg$", url.path)
        if m:
            return self.send_file(sound_path(m.group(1)), "audio/ogg")
        m = re.match(r"^/takes/(.+\.mp3)$", url.path)
        if m:
            return self.send_file(VG.take_path(unquote(m.group(1))), "audio/mpeg")
        if url.path == "/preview.ogg":
            return self.send_file(os.path.join(VG.work, "preview.ogg"), "audio/ogg")
        if not url.path.startswith("/api/"):
            return self.send(404, {"error": "not found"})
        if not self.allowed():
            return self.send(403, {"error": "forbidden"})
        try:
            return self.api_get(url.path, q)
        except voicegen.ApiError as e:
            return self.send(502 if e.status == 0 else 400, {"error": str(e), "code": e.code})
        except (RuntimeError, ValueError) as e:
            return self.send(400, {"error": str(e)})

    def api_get(self, path, q):
        if path == "/api/ping":
            return self.send(200, {"ok": True})
        if path == "/api/catalog":
            return self.send(200, {
                "hooks": load_json(os.path.join(CATALOG, "hooks.json"), {}).get("hooks", []),
                "dialogue": dialogue(),
                "sounds": list_sounds(),
                "folders": list_folders(),
            })
        if path == "/api/config":
            return self.send(200, load_config())
        if path == "/api/cast":
            return self.send(200, VG.load_cast())
        if path == "/api/takes":
            return self.send(200, VG.load_takes())
        if path == "/api/voice/status":
            key, source = voicegen.key_info()
            return self.send(200, {
                "key": bool(key), "key_source": source,
                "key_hint": ("…" + key[-4:]) if len(key) > 8 else "",
                "tenacity": VG.tenacity.connected(),
                "tenacity_installed": os.path.exists(r"C:\Program Files\Tenacity\tenacity.exe"),
                "ffmpeg": bool(shutil.which("ffmpeg")),
            })
        if path == "/api/voice/jobs":
            return self.send(200, VG.state(int((q.get("since") or ["0"])[0])))
        if path == "/api/eleven/voices":
            res = voicegen.eleven("GET", "/v1/voices")
            return self.send(200, [{"voice_id": v["voice_id"], "name": v.get("name", ""),
                                    "category": v.get("category", ""), "labels": v.get("labels") or {},
                                    "preview_url": v.get("preview_url") or ""}
                                   for v in res.get("voices", [])])
        if path == "/api/eleven/models":
            res = voicegen.eleven("GET", "/v1/models")
            return self.send(200, [{"model_id": m["model_id"], "name": m.get("name", m["model_id"]),
                                    "cost": m.get("token_cost_factor", 1)}
                                   for m in res if m.get("can_do_text_to_speech", True)])
        if path == "/api/eleven/subscription":
            res = voicegen.eleven("GET", "/v1/user/subscription")
            return self.send(200, {k: res.get(k) for k in ("tier", "character_count", "character_limit",
                                                            "next_character_count_reset_unix")})
        if path == "/api/tenacity/commands":
            cmds = VG.tenacity.get_commands()
            return self.send(200, [{"id": c.get("id"), "name": c.get("name"), "params": c.get("params", []),
                                    "tip": c.get("tip", "")} for c in cmds])
        if path == "/api/tenacity/macros":
            return self.send(200, voicegen.list_macros())
        return self.send(404, {"error": "not found"})

    # -------------------------------------------------------------- PUT
    def do_PUT(self):
        path = urlparse(self.path).path
        if not self.allowed():
            return self.send(403, {"error": "forbidden"})
        try:
            data = self.body_json()
            if not isinstance(data, dict):
                raise ValueError("expected an object")
        except ValueError as e:
            return self.send(400, {"error": str(e)})
        if path == "/api/config":
            save_config(data)
            return self.send(200, {"ok": True})
        if path == "/api/cast":
            write_json(VG.cast_path, data, backup=True)
            return self.send(200, {"ok": True})
        if path == "/api/voice/key":
            try:
                voicegen.set_key(str(data.get("key", "")))
            except OSError as e:
                return self.send(400, {"error": str(e)})
            return self.send(200, {"ok": True})
        return self.send(404, {"error": "not found"})

    # -------------------------------------------------------------- POST
    def do_POST(self):
        global bye_at
        url = urlparse(self.path)
        if url.path == "/api/bye":
            # sent by the closing page (navigator.sendBeacon can't add headers,
            # so the browser's Origin header is what's checked)
            if self.headers.get("Origin") in ("http://127.0.0.1:%d" % PORT, "http://localhost:%d" % PORT):
                bye_at = time.time() + BYE_GRACE
                return self.send(200, {"ok": True})
            return self.send(403, {"error": "forbidden"})
        if not self.allowed():
            return self.send(403, {"error": "forbidden"})
        q = parse_qs(url.query)
        try:
            if url.path == "/api/upload":
                return self.upload(q)
            data = self.body_json() or {}
            return self.api_post(url.path, data)
        except voicegen.ApiError as e:
            return self.send(400, {"error": str(e), "code": e.code})
        except (ValueError, RuntimeError, OSError, subprocess.CalledProcessError) as e:
            return self.send(400, {"error": str(e)})

    def upload(self, q):
        name = (q.get("name") or [""])[0].lower()
        name = re.sub(r"[^a-z0-9_]+", "_", name).strip("_")[:80]
        if not NAME_RE.match(name):
            raise ValueError("bad name")
        folder = clean_folder((q.get("folder") or [""])[0])
        replace = (q.get("replace") or ["0"])[0] == "1"
        index = sound_index()
        if replace and name in index:
            os.remove(sound_path(name, index[name]))
            del index[name]
        name = unique_name(name, index)
        ext = os.path.splitext((q.get("filename") or ["x.wav"])[0])[1].lower() or ".wav"
        data = self.read_body()
        dst_dir = os.path.join(SOUNDS, *(folder.split("/") if folder else []))
        os.makedirs(dst_dir, exist_ok=True)
        with tempfile.NamedTemporaryFile(suffix=ext, delete=False) as t:
            t.write(data)
            tmpname = t.name
        try:
            convert(tmpname, os.path.join(dst_dir, name + ".ogg"))
        finally:
            os.unlink(tmpname)
        return self.send(200, {"name": name, "folder": folder})

    def api_post(self, path, data):
        if path == "/api/folders":
            folder = clean_folder(data.get("folder", ""))
            if not folder:
                raise ValueError("folder name needed")
            os.makedirs(os.path.join(SOUNDS, *folder.split("/")), exist_ok=True)
            return self.send(200, {"folder": folder})
        if path == "/api/folders/delete":
            folder = clean_folder(data.get("folder", ""))
            full = os.path.join(SOUNDS, *folder.split("/")) if folder else None
            if not full or not os.path.isdir(full):
                raise ValueError("no such folder")
            if any(files for _, _, files in os.walk(full)):
                raise ValueError("Only empty folders can be deleted")
            shutil.rmtree(full)
            return self.send(200, {"ok": True})
        if path == "/api/move":
            folder = clean_folder(data.get("folder", ""))
            moved = []
            index = sound_index()
            for name in data.get("names", []):
                if name in index and index[name] != folder:
                    dst_dir = os.path.join(SOUNDS, *(folder.split("/") if folder else []))
                    os.makedirs(dst_dir, exist_ok=True)
                    shutil.move(sound_path(name, index[name]), os.path.join(dst_dir, name + ".ogg"))
                    moved.append(name)
            return self.send(200, {"moved": moved})
        if path == "/api/voice/queue":
            items = []
            known = dialogue_by_id()
            for it in data.get("items", []):
                if it.get("line") in known and it.get("action") in ("generate", "process"):
                    items.append({"line": it["line"], "action": it["action"]})
            return self.send(200, {"jobs": VG.enqueue(items)})
        if path == "/api/voice/cancel":
            VG.cancel()
            return self.send(200, {"ok": True})
        if path == "/api/voice/take":
            VG.set_take(data.get("line", ""), int(data.get("index", 0)))
            return self.send(200, {"ok": True})
        if path == "/api/voice/plan":
            cast = VG.load_cast()
            out = []
            for line in data.get("lines", [])[:5000]:
                try:
                    _, speaker, sc, text = VG.line_plan(line, cast)
                    out.append({"line": line, "speaker": speaker, "chars": len(text),
                                "voice": bool(sc.get("voice_id")), "model": sc.get("model_id", "")})
                except ValueError:
                    pass
            return self.send(200, out)
        if path == "/api/voice/preview":
            # {steps, rate, source: "take:<line id>" | "sound:<name>"}
            src = data.get("source", "")
            if src.startswith("take:"):
                t = VG.load_takes().get(src[5:])
                if not t or not t["takes"]:
                    raise ValueError("That line has no take yet")
                path_in = VG.take_path(t["takes"][t.get("current", 0)]["file"])
            elif src.startswith("sound:"):
                path_in = sound_path(src[6:])
            else:
                raise ValueError("Choose something to test the preset on")
            if not path_in or not os.path.exists(path_in):
                raise ValueError("Source audio not found")
            VG.preview(path_in, data.get("steps", []), {"rate": data.get("rate") or 11025, "quality": 5})
            return self.send(200, {"url": "/preview.ogg"})
        if path == "/api/tenacity/macros":
            name = voicegen.save_macro(str(data.get("name", "")), data.get("steps", []))
            return self.send(200, {"name": name})
        return self.send(404, {"error": "not found"})


def main():
    global PORT
    ports = [a for a in sys.argv[1:] if a.isdigit()]
    PORT = int(ports[0]) if ports else 8765
    os.makedirs(SOUNDS, exist_ok=True)
    srv = Server(("127.0.0.1", PORT), Handler)
    url = "http://127.0.0.1:%d/" % PORT
    print("NetHack Voxel sound editor: " + url + "  (stops when the editor tab is closed)")
    if "--no-browser" not in sys.argv:
        threading.Timer(0.5, lambda: webbrowser.open(url)).start()
    if "--stay" not in sys.argv:
        threading.Thread(target=watchdog, args=(srv,), daemon=True).start()
    srv.serve_forever()
    print("The editor page was closed, so the editor stopped.")


def watchdog(srv):
    while True:
        time.sleep(1)
        if VG.busy():
            continue  # let queued voice lines finish first
        now = time.time()
        if (bye_at and now > bye_at) or now - last_seen > SILENCE_LIMIT:
            srv.shutdown()
            return


if __name__ == "__main__":
    main()
