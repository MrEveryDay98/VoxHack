"""Sound extraction for the VoxHack Editor (the Extract sounds tab).

A long recording (a sound pack's demo reel, a field recording...) is
uploaded once and kept in voice_work/extract/; the page marks clips on its
waveform and asks for them to be cut out. Each clip is cut with ffmpeg,
optionally with a short fade at its start and end (so it doesn't click),
and saved as Ogg Vorbis in the sounds folder, like any uploaded sound.
"""
import os
import shutil
import subprocess
import uuid

MAX_CLIPS = 500
MAX_FADE_MS = 2000

_source = {"id": None, "path": None}


def _ffmpeg():
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise RuntimeError("ffmpeg was not found on PATH")
    return ffmpeg


def upload_source(work, filename, data):
    """Keep the long file (one at a time: a new one replaces the last);
    returns its id, which a save names."""
    if not data:
        raise ValueError("the file is empty")
    folder = os.path.join(work, "extract")
    os.makedirs(folder, exist_ok=True)
    for f in os.listdir(folder):
        os.remove(os.path.join(folder, f))
    ext = os.path.splitext(filename or "")[1].lower()
    if not ext or len(ext) > 6 or not ext[1:].isalnum():
        ext = ".bin"
    path = os.path.join(folder, "source" + ext)
    with open(path, "wb") as f:
        f.write(data)
    _source["id"], _source["path"] = uuid.uuid4().hex, path
    return _source["id"]


def cut(src, dst, start, end, fade_ms):
    """Clip [start, end) seconds of src into dst (.ogg), with fade_ms of
    fade in and out (0: none; never more than half the clip)."""
    dur = end - start
    cmd = [_ffmpeg(), "-loglevel", "error", "-y", "-ss", "%.4f" % start, "-t", "%.4f" % dur,
           "-i", src, "-vn"]
    fade = min(fade_ms / 1000.0, dur / 2)
    if fade > 0:
        cmd += ["-af", "afade=t=in:st=0:d=%.4f,afade=t=out:st=%.4f:d=%.4f" % (fade, dur - fade, fade)]
    cmd += ["-c:a", "libvorbis", "-q:a", "5", dst]
    subprocess.run(cmd, check=True)


def save_clips(data, dst_dir, name_ok, unique):
    """Cut the clips data asks for out of the uploaded file into dst_dir.
    name_ok(name) says if a name is allowed; unique(name) makes it unique
    among the game's sounds (and claims it). Returns the names saved."""
    if not _source["id"] or data.get("source") != _source["id"] or not os.path.exists(_source["path"]):
        raise ValueError("the long file is gone: open it again")
    clips = data.get("clips")
    if not isinstance(clips, list) or not clips:
        raise ValueError("no clips to save")
    if len(clips) > MAX_CLIPS:
        raise ValueError("too many clips (at most %d at a time)" % MAX_CLIPS)
    fade_ms = float(data.get("fade_ms") or 0) if data.get("fade") else 0
    fade_ms = max(0.0, min(fade_ms, MAX_FADE_MS))
    jobs = []
    for c in clips:
        name = str(c.get("name", "")).lower()
        if not name_ok(name):
            raise ValueError("bad clip name: %r (a-z, 0-9 and _ only)" % name)
        start, end = float(c.get("start", 0)), float(c.get("end", 0))
        if not (start >= 0 and end > start + 0.005):
            raise ValueError("clip %s: its end must come after its start" % name)
        jobs.append((name, start, end))
    os.makedirs(dst_dir, exist_ok=True)
    saved = []
    for name, start, end in jobs:
        name = unique(name)
        cut(_source["path"], os.path.join(dst_dir, name + ".ogg"), start, end, fade_ms)
        saved.append(name)
    return saved
