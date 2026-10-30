"""Make the intro editor world: the opening's forest, made by Luanti's world
generator (rolling grass, NetHack's trees), where you put down the
camera's way through it (game/nethackvoxel/mods/nhv/intro_editor.lua).

    python -I tools/make_intro_world.py [name] [--run]

Creates external/luanti/worlds/<name> (intro_editor if not given) and
prints how to open it; --run opens it straight away. In the world, the
forest is x, z 0 to 255; /intro_save saves it for the game
(mod_data/nhv/intro). Delete the world folder for a new forest.
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENGINE = os.path.join(ROOT, "external", "luanti")

# the world generator's settings: low rolling hills, no caves, mountains or
# water (the game's biome and trees: intro_editor.lua)
MAP_META = """mg_name = v7
seed = 2207
water_level = -64
mg_flags = nocaves, nodungeons, light, decorations, biomes, noores
mgv7_spflags = nomountains, noridges, nofloatlands, nocaverns
[end_of_params]
"""


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    name = args[0] if args else "intro_editor"
    world = os.path.join(ENGINE, "worlds", name)
    if not os.path.isdir(world):
        os.makedirs(world)
        with open(os.path.join(world, "world.mt"), "w", encoding="utf-8") as f:
            f.write("gameid = nethackvoxel\nbackend = sqlite3\nplayer_backend = sqlite3\n"
                    "auth_backend = sqlite3\nmod_storage_backend = sqlite3\n")
        with open(os.path.join(world, "map_meta.txt"), "w", encoding="utf-8") as f:
            f.write(MAP_META)
        with open(os.path.join(world, "nhv_intro"), "w", encoding="utf-8") as f:
            f.write("intro editor\n")
        print("Made", world)
    else:
        print("Already there:", world)
    cmd = [os.path.join(ENGINE, "bin", "luanti.exe"), "--go", "--world", os.path.join("worlds", name)]
    print("Open it with:\n  cd", ENGINE, "\n  " + " ".join(["bin\\luanti.exe", "--go", "--world", "worlds\\" + name]))
    if "--run" in sys.argv:
        subprocess.Popen(cmd, cwd=ENGINE)


if __name__ == "__main__":
    main()
