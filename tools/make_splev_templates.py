"""Write game/nethackvoxel/mods/nhv/splev_templates.txt: the fixed regions of
every special level variant (Minetown's town, the Oracle's centre, Medusa's
island, Sokoban...), with their terrain, for the area prefab editor and for
building those levels from area prefabs in the game.

It runs NetHack headlessly (build/nhcore/nhvtest.exe, built by deploy.sh) in
wizard mode, once per role so every quest's levels are included, with the
#nhvsplevdump command, and merges what they write.

Usage: python -I tools/make_splev_templates.py
Run it again whenever NetHack's level files change.

Each line: "<proto> <n> <x> <y> <w> <h> <terrain>": region n of the level
file <proto> was at <x>,<y> (w x h squares) when it was built here (some
levels place it differently each time; the game is told where), and its
terrain types row by row, one character each ('0' + type).
"""
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXE = os.path.join(ROOT, "build", "nhcore", "nhvtest.exe")
DATA = os.path.join(ROOT, "build", "nhcore", "nhdata")
OUT = os.path.join(ROOT, "game", "nethackvoxel", "mods", "nhv", "splev_templates.txt")
ROLES = ["archeologist", "barbarian", "caveman", "healer", "knight", "monk",
         "priest", "rogue", "ranger", "samurai", "tourist", "valkyrie", "wizard"]


def dump(role):
    # (a short path: NetHack's file names are limited in length)
    work = tempfile.mkdtemp(prefix="nhvs", dir=os.environ.get("TEMP"))
    try:
        env = dict(os.environ, NHVTEST_WIZARD="1",
                   NETHACKOPTIONS="role:%s,race:human,gender:male,align:neutral" % role)
        if role in ("knight", "samurai"):  # (lawful only)
            env["NETHACKOPTIONS"] = "role:%s,race:human,gender:male,align:lawful" % role
        elif role in ("archeologist", "caveman", "healer", "monk", "priest", "ranger",
                      "tourist", "valkyrie", "wizard"):
            env["NETHACKOPTIONS"] = "role:%s,race:human,gender:female" % role
        r = subprocess.run([EXE, DATA, work, "free", "#", "text:nhvsplevdump"],
                           cwd=work, env=env, capture_output=True, text=True, timeout=600)
        path = os.path.join(work, "splev_templates.txt")
        if not os.path.exists(path):
            sys.exit("%s: no templates written\n%s" % (role, r.stdout[-2000:]))
        with open(path) as f:
            return [line.rstrip("\n") for line in f if line.strip()]
    finally:
        shutil.rmtree(work, ignore_errors=True)


def main():
    if not os.path.exists(EXE):
        sys.exit("build NetHack first (tools/deploy.sh): " + EXE)
    regions = {}
    for role in ROLES:
        lines = dump(role)
        for line in lines:
            proto, n = line.split(" ", 2)[:2]
            regions.setdefault((proto, int(n)), line)
        print("%-12s %d regions" % (role, len(lines)))
    with open(OUT, "w", newline="\n") as f:
        f.write("# Special level fixed regions (tools/make_splev_templates.py)\n")
        for key in sorted(regions):
            f.write(regions[key] + "\n")
    print("%d regions -> %s" % (len(regions), OUT))


if __name__ == "__main__":
    main()
