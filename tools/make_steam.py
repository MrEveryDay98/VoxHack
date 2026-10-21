"""Make VoxHack's Steam build: dist/steam/content (what a Steam install holds)
and dist/steam/scripts (the SteamPipe scripts that upload it).

The content is the release (make_release.py) laid out for Steam:

    engine/                     Luanti, NetHack and the game
        nhv_defaults.conf       the game's default settings (not minetest.conf:
                                that's the player's, and a Steam update or
                                "Verify integrity" would put a shipped one back)
    Launchers/                  Reset NetHack Save, Level Atlas
    licenses/, CREDITS.txt, README.txt

Steam starts engine\\bin\\luanti.exe itself (steam/README.md: the launch
option), so there's no shortcut maker and no Play launcher.

The app and depot ids are in steam/steam.json (from the Steamworks partner
site). Uploading needs your Steam partner login, so you run it yourself:

    steamcmd +login <your Steam login> +run_app_build "<...>\\dist\\steam\\scripts\\app_build.vdf" +quit

Usage: python -I tools/make_steam.py [--desc "what's in this build"]
"""
import json
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_release as rel  # noqa: E402

ROOT = rel.ROOT
OUT = os.path.join(ROOT, "dist", "steam")
CONTENT = os.path.join(OUT, "content")
SCRIPTS = os.path.join(OUT, "scripts")

# (in a Steam install: Steam starts the game, and keeps shortcuts itself)
NOT_ON_STEAM = ["Create Play Shortcut.bat", os.path.join("Launchers", "Play VoxHack.bat"),
	os.path.join("Launchers", "make_shortcut.ps1"), os.path.join("engine", "minetest.conf")]

README = """VoxHack
=======

NetHack 3.7 in first person, built on the Luanti engine.

Play it from Steam. Esc > Help in the game lists every key.

Your game is kept in this folder:
  engine\\worlds\\nethack    your character, its save, the high scores
  engine\\minetest.conf      your settings (made when you change one)
Uninstalling the game deletes this folder: copy engine\\worlds\\nethack
somewhere first to keep your character.

Starting over
-------------
Launchers\\Reset NetHack Save.bat deletes your saved character (with the game
closed), so the next game starts a new one. High scores are kept.

The level atlas
---------------
Launchers\\VoxHack Level Atlas.bat asks for a seed (any whole number) and
builds every level of that game side by side, terrain only - to look at how
the dungeon's pieces fit together. K: fly, H: noclip; /atlas lists the
levels, /atlas <number> goes to one, /atlas ceilings takes the ceilings off.

Source code and licences
------------------------
VoxHack is based on NetHack and is not an official NetHack release. Its full
source, with the modified NetHack and Luanti, is at
https://github.com/MrEveryDay98/VoxHack (each version is tagged there).
CREDITS.txt lists what the game is made of and under which licence; the
licenses folder has the licence texts.
"""

APP_BUILD = '''"AppBuild"
{{
	"AppID" "{app}"
	"Desc" "{desc}"
	"ContentRoot" "{content}"
	"BuildOutput" "{output}"
	"SetLive" ""
	"Depots"
	{{
		"{depot}" "depot_build.vdf"
	}}
}}
'''

DEPOT_BUILD = '''"DepotBuild"
{{
	"DepotID" "{depot}"
	"FileMapping"
	{{
		"LocalPath" "*"
		"DepotPath" "."
		"Recursive" "1"
	}}
	// (the player's own files: never shipped, never removed by an update)
	"FileExclusion" "engine\\\\minetest.conf"
	"FileExclusion" "engine\\\\debug.txt"
	"InstallScript" ""
}}
'''


def vdf_path(p):
	return p.replace("\\", "\\\\")


def check_engine():
	# (an engine from before nhv_defaults.conf would start with Luanti's own
	# settings: windowed, 72 degrees field of view, blurry textures)
	with open(os.path.join(rel.LUANTI, "bin", "luanti.exe"), "rb") as f:
		if b"nhv_defaults.conf" not in f.read():
			sys.exit("luanti.exe doesn't read nhv_defaults.conf yet: rebuild it (tools/deploy.sh)")


def main():
	rel.check_built()
	check_engine()
	desc = "VoxHack " + rel.commit()
	if "--desc" in sys.argv:
		desc = sys.argv[sys.argv.index("--desc") + 1]
	with open(os.path.join(ROOT, "steam", "steam.json")) as f:
		ids = json.load(f)

	if os.path.exists(OUT):
		shutil.rmtree(OUT)
	os.makedirs(CONTENT)
	rel.stage(CONTENT)
	for p in NOT_ON_STEAM:
		p = os.path.join(CONTENT, p)
		if os.path.exists(p):
			os.remove(p)
	rel.write(os.path.join(CONTENT, "engine", "nhv_defaults.conf"), rel.CONF, crlf=False)
	rel.write(os.path.join(CONTENT, "README.txt"), README)

	os.makedirs(SCRIPTS)
	rel.write(os.path.join(SCRIPTS, "app_build.vdf"), APP_BUILD.format(
		app=ids["app_id"], depot=ids["depot_id"], desc=desc.replace('"', "'"),
		content=vdf_path(CONTENT), output=vdf_path(os.path.join(OUT, "output"))))
	rel.write(os.path.join(SCRIPTS, "depot_build.vdf"), DEPOT_BUILD.format(depot=ids["depot_id"]))

	size = sum(os.path.getsize(os.path.join(d, f)) for d, _, fs in os.walk(CONTENT) for f in fs)
	print("%s (%.1f MB)" % (CONTENT, size / 1e6))
	if str(ids["app_id"]).startswith("0"):
		print("note: steam/steam.json still has placeholder ids - put your app and depot ids in it")
	print('upload: steamcmd +login <your Steam login> +run_app_build "%s" +quit'
		% os.path.join(SCRIPTS, "app_build.vdf"))


if __name__ == "__main__":
	main()
