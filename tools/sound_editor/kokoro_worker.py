"""Kokoro text-to-speech worker for the sound editor.

Runs in the Kokoro virtual environment (voice_work/kokoro/venv), started by
voicegen.py, so the editor itself needs no packages. One JSON request per
line on stdin, one JSON reply per line on stdout:

  {"cmd": "voices"}
      -> {"ok": true, "voices": ["af_heart", ...]}
  {"cmd": "say", "text": ..., "voice": "af_heart" | "af_heart*0.6+bf_emma*0.4",
   "speed": 1.0, "lang": "en-us", "out": "C:/.../take.wav"}
      -> {"ok": true, "seconds": 3.2}
Errors come back as {"ok": false, "error": "..."}.

usage: python kokoro_worker.py <model.onnx> <voices.bin>
"""
import json
import sys


def main():
    out = sys.stdout
    sys.stdout = sys.stderr  # stray prints from libraries mustn't break the replies
    import soundfile as sf
    from kokoro_onnx import Kokoro

    k = Kokoro(sys.argv[1], sys.argv[2])
    names = set(k.get_voices())

    def style(spec):
        """"a" or "a*0.6+b*0.4": one voice, or a weighted blend of several"""
        parts = []
        for part in str(spec).split("+"):
            name, _, w = part.strip().partition("*")
            name = name.strip()
            if name not in names:
                raise ValueError("Kokoro has no voice called %r" % name)
            parts.append((name, float(w) if w else 1.0))
        if len(parts) == 1:
            return parts[0][0]
        total = sum(w for _, w in parts) or 1.0
        return sum(k.get_voice_style(n) * (w / total) for n, w in parts)

    out.write(json.dumps({"ok": True, "ready": True}) + "\n")
    out.flush()
    for line in sys.stdin:
        if not line.strip():
            continue
        try:
            req = json.loads(line)
            if req.get("cmd") == "voices":
                reply = {"ok": True, "voices": sorted(names)}
            elif req.get("cmd") == "say":
                samples, rate = k.create(req["text"], voice=style(req["voice"]),
                                         speed=float(req.get("speed") or 1.0),
                                         lang=req.get("lang") or "en-us")
                sf.write(req["out"], samples, rate, subtype="PCM_16")
                reply = {"ok": True, "seconds": round(len(samples) / rate, 2)}
            else:
                reply = {"ok": False, "error": "unknown command"}
        except Exception as e:  # noqa: BLE001 - every failure goes back to the editor
            reply = {"ok": False, "error": "%s: %s" % (type(e).__name__, e)}
        out.write(json.dumps(reply) + "\n")
        out.flush()


if __name__ == "__main__":
    main()
