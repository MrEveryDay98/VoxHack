"""Write game/nethackvoxel/mods/nhv/splev_templates.txt: the fixed regions of
every special level variant (Minetown's town, the Oracle's centre, Medusa's
island, Sokoban...), with their terrain, for the area prefab editor and for
building those levels from area prefabs in the game.

It runs NetHack headlessly (build/nhcore/nhvtest.exe, built by deploy.sh) in
wizard mode, once per role so every quest's levels are included, with the
#nhvsplevdump command, and merges what they write.

Usage: python -I tools/make_splev_templates.py
Run it again whenever NetHack's level files change.

It also writes tools/sound_editor/splev_levels.txt: every special level
whole, as NetHack built it here (before any flip), with its stair, branch
and teleport regions, stairs and portals - the VoxHack Editor's Special
levels page draws them.

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
LEVELS_OUT = os.path.join(ROOT, "tools", "sound_editor", "splev_levels.txt")
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
            lines = [line.rstrip("\n") for line in f if line.strip()]
        levels = []
        path = os.path.join(work, "splev_levels.txt")
        if os.path.exists(path):
            with open(path) as f:
                levels = [line.rstrip("\n") for line in f if line.strip()]
        return lines, levels
    finally:
        shutil.rmtree(work, ignore_errors=True)


def main():
    if not os.path.exists(EXE):
        sys.exit("build NetHack first (tools/deploy.sh): " + EXE)
    regions = {}
    levels = {}  # proto -> its lines (from the first role that has it)
    for role in ROLES:
        lines, level_lines = dump(role)
        for line in lines:
            proto, n = line.split(" ", 2)[:2]
            regions.setdefault((proto, int(n)), line)
        here = {}
        for line in level_lines:
            here.setdefault(line.split(" ", 2)[1], []).append(line)
        for proto, ls in here.items():
            levels.setdefault(proto, ls)
        print("%-12s %d regions" % (role, len(lines)))
    with open(OUT, "w", newline="\n") as f:
        f.write("# Special level fixed regions (tools/make_splev_templates.py)\n")
        for key in sorted(regions):
            f.write(regions[key] + "\n")
    print("%d regions -> %s" % (len(regions), OUT))
    with open(LEVELS_OUT, "w", newline="\n") as f:
        f.write("# Special levels whole (tools/make_splev_templates.py)\n")
        for proto in sorted(levels):
            f.write("\n".join(levels[proto]) + "\n")
    print("%d levels -> %s" % (len(levels), LEVELS_OUT))


if __name__ == "__main__":
    main()
