"""Make a level-atlas world: every level of a game with the given seed,
built side by side (one column per dungeon, levels stacked by depth),
terrain only, to see how the prefabs fit together in real levels.

    python -I tools/make_atlas_world.py <seed> [--run]

Creates external/luanti/worlds/atlas_<seed> (the engine's worlds folder)
and prints how to open it; --run opens it straight away. The first time
it's opened the atlas is built (a minute or two: you'll see the progress
in the chat); after that it opens ready. Same seed, same levels. Delete
the world folder to build it again (after prefab changes, say).
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENGINE = os.path.join(ROOT, "external", "luanti")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1 or not args[0].isdigit() or int(args[0]) < 1:
        sys.exit("usage: python -I tools/make_atlas_world.py <seed (a positive number)> [--run]")
    seed = int(args[0])
    name = "atlas_%d" % seed
    world = os.path.join(ENGINE, "worlds", name)
    if not os.path.isdir(world):
        os.makedirs(world)
        with open(os.path.join(world, "world.mt"), "w", encoding="utf-8") as f:
            f.write("gameid = nethackvoxel\nbackend = sqlite3\nplayer_backend = sqlite3\n"
                    "auth_backend = sqlite3\nmod_storage_backend = sqlite3\n")
        with open(os.path.join(world, "nhv_atlas"), "w", encoding="utf-8") as f:
            f.write("%d\n" % seed)
        print("Made", world)
    else:
        print("Already there:", world)
    cmd = [os.path.join(ENGINE, "bin", "luanti.exe"), "--go", "--world", os.path.join("worlds", name)]
    print("Open it with:\n  cd", ENGINE, "\n  " + " ".join(['bin\\luanti.exe', "--go", "--world", "worlds\\" + name]))
    if "--run" in sys.argv:
        subprocess.Popen(cmd, cwd=ENGINE)


if __name__ == "__main__":
    main()
