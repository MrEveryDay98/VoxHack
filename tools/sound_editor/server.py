"""Local server for the NetHack Voxel sound & voice editor.

Serves the editor page and reads/writes the game's sound data in
game/nethackvoxel/mods/nhv_sounds:
  config.json        hook -> sounds, music, voices, master volumes
  sounds/*.ogg       sound effects, music and voice recordings
  catalog/*.json     hooks.json (every hook) and dialogue.json (every line)

Only listens on 127.0.0.1. Uploaded audio is converted to Ogg Vorbis with
ffmpeg. The game picks up changes to config.json within a couple of seconds.

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
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
MOD = os.path.join(ROOT, "game", "nethackvoxel", "mods", "nhv_sounds")
SOUNDS = os.path.join(MOD, "sounds")
CONFIG = os.path.join(MOD, "config.json")
CATALOG = os.path.join(MOD, "catalog")
STATIC = {"/": ("index.html", "text/html"), "/app.js": ("app.js", "text/javascript"),
          "/style.css": ("style.css", "text/css")}
NAME_RE = re.compile(r"^[a-z0-9_]{1,80}$")


def load_json(path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def list_sounds():
    out = []
    for f in sorted(os.listdir(SOUNDS)):
        if f.endswith(".ogg"):
            out.append({"name": f[:-4], "size": os.path.getsize(os.path.join(SOUNDS, f))})
    return out


def convert(src, name):
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise RuntimeError("ffmpeg was not found on PATH")
    dst = os.path.join(SOUNDS, name + ".ogg")
    subprocess.run([ffmpeg, "-loglevel", "error", "-y", "-i", src, "-vn",
                    "-c:a", "libvorbis", "-q:a", "5", dst], check=True)
    return name


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

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

    def do_GET(self):
        url = urlparse(self.path)
        if url.path in STATIC:
            fname, ctype = STATIC[url.path]
            with open(os.path.join(HERE, fname), "rb") as f:
                return self.send(200, f.read(), ctype + "; charset=utf-8")
        if url.path == "/api/catalog":
            return self.send(200, {
                "hooks": load_json(os.path.join(CATALOG, "hooks.json"), {}).get("hooks", []),
                "dialogue": load_json(os.path.join(CATALOG, "dialogue.json"), {}).get("entries", []),
                "sounds": list_sounds(),
            })
        if url.path == "/api/config":
            return self.send(200, load_json(CONFIG, {"version": 1, "hooks": {}, "voices": {}}))
        m = re.match(r"^/sounds/([a-z0-9_]+)\.ogg$", url.path)
        if m:
            path = os.path.join(SOUNDS, m.group(1) + ".ogg")
            if os.path.exists(path):
                with open(path, "rb") as f:
                    return self.send(200, f.read(), "audio/ogg")
        self.send(404, {"error": "not found"})

    def read_body(self):
        n = int(self.headers.get("Content-Length", "0"))
        if n > 200 * 1024 * 1024:
            raise ValueError("file too large")
        return self.rfile.read(n)

    def do_PUT(self):
        if urlparse(self.path).path != "/api/config":
            return self.send(404, {"error": "not found"})
        try:
            cfg = json.loads(self.read_body().decode("utf-8"))
            if not isinstance(cfg, dict):
                raise ValueError("config must be an object")
        except ValueError as e:
            return self.send(400, {"error": str(e)})
        if os.path.exists(CONFIG):
            shutil.copyfile(CONFIG, CONFIG + ".bak")
        tmp = CONFIG + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(cfg, f, indent=1)
        os.replace(tmp, CONFIG)
        self.send(200, {"ok": True})

    def do_POST(self):
        url = urlparse(self.path)
        if url.path != "/api/upload":
            return self.send(404, {"error": "not found"})
        q = parse_qs(url.query)
        name = (q.get("name") or [""])[0].lower()
        name = re.sub(r"[^a-z0-9_]+", "_", name).strip("_")
        if not NAME_RE.match(name):
            return self.send(400, {"error": "bad name"})
        ext = os.path.splitext((q.get("filename") or ["x.wav"])[0])[1].lower() or ".wav"
        try:
            data = self.read_body()
            with tempfile.NamedTemporaryFile(suffix=ext, delete=False) as t:
                t.write(data)
                tmpname = t.name
            try:
                convert(tmpname, name)
            finally:
                os.unlink(tmpname)
        except (ValueError, RuntimeError, subprocess.CalledProcessError) as e:
            return self.send(400, {"error": str(e)})
        self.send(200, {"name": name})


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    os.makedirs(SOUNDS, exist_ok=True)
    srv = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    url = "http://127.0.0.1:%d/" % port
    print("NetHack Voxel sound editor: " + url + "  (close this window to stop)")
    threading.Timer(0.5, lambda: webbrowser.open(url)).start()
    srv.serve_forever()


if __name__ == "__main__":
    main()
