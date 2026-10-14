"""Make a release zip of NetHack Voxel: dist/NetHackVoxel-<date>-<commit>.zip

Packs the game as it's built now (run tools/deploy.sh first), with no saves,
no editors and no developer tools. Inside the zip:

    NetHack Voxel/
        Create Play Shortcut.bat    makes a "Play NetHack Voxel" shortcut
        README.txt
        Launchers/                  Play NetHack Voxel, Reset NetHack Save
        engine/                     Luanti, NetHack and the game
        licenses/

Usage: python -I tools/make_release.py [--keep]  (--keep: keep the unpacked
copy in dist/ too, e.g. to try it)
"""
import datetime
import fnmatch
import os
import shutil
import subprocess
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LUANTI = os.path.join(ROOT, "external", "luanti")
GAME = os.path.join(ROOT, "game", "nethackvoxel")
DIST = os.path.join(ROOT, "dist")
TOP = "NetHack Voxel"

# from the engine folder (external/luanti)
ENGINE_DIRS = ["builtin", "client", "fonts", "textures"]
# left out of the game: backups and the editors' own files
GAME_SKIP = ["*.bak", "*.before-*", "voice_cast*.json", "__pycache__"]
# the prefabs and sizes made in the editor (the game reads them from mod_data)
MOD_DATA = ["prefabs.dat", "scales.dat"]
LAUNCHERS = ["Play NetHack Voxel.bat", "make_shortcut.ps1"]
# (renamed: in a release it's for starting over, not just testing)
RESET = ("Reset NetHack Save (testing).bat", "Reset NetHack Save.bat")

WORLD_MT = """gameid = nethackvoxel
backend = sqlite3
player_backend = sqlite3
auth_backend = sqlite3
mod_storage_backend = sqlite3
"""

CONF = """# NetHack Voxel settings. The game adds to this as you change its options
# (Inventory > Graphics / NetHack options).
window_maximized = true
fov = 90
tone_mapping = false
mip_map = false
bilinear_filter = false
trilinear_filter = false
anisotropic_filter = true
"""

README = """NetHack Voxel
=============

NetHack 3.7 in first person, built on the Luanti engine. Windows only.

Playing
-------
Run "Create Play Shortcut.bat" once: it makes a "Play NetHack Voxel" shortcut
in this folder (and on your Desktop if you like). Or use
Launchers\\Play NetHack Voxel.bat.

Run "Create Play Shortcut.bat" again if you move this folder.

Your saved game, high scores and settings are kept in this folder:
  engine\\worlds\\nethack    the game and its save
  engine\\minetest.conf      settings

Starting over
-------------
Launchers\\Reset NetHack Save.bat deletes your saved character (with the game
closed), so the next game starts a new one. High scores are kept.

Licenses
--------
See the licenses folder: NetHack (NetHack General Public License), Luanti
(LGPL 2.1+), the GeneralUser GS SoundFont, and Luanti's bundled libraries.
"""


def skip(name):
	return any(fnmatch.fnmatch(name, p) for p in GAME_SKIP)


def copytree(src, dst, ignore_names=None):
	shutil.copytree(src, dst, ignore=ignore_names, dirs_exist_ok=True)


def write(path, text, crlf=True):
	os.makedirs(os.path.dirname(path), exist_ok=True)
	with open(path, "w", newline="") as f:
		f.write(text.replace("\n", "\r\n") if crlf else text)


def commit():
	try:
		return subprocess.check_output(["git", "-C", ROOT, "rev-parse", "--short", "HEAD"],
				text=True).strip()
	except (OSError, subprocess.CalledProcessError):
		return "local"


def check_built():
	need = [os.path.join(LUANTI, "bin", "luanti.exe"), os.path.join(LUANTI, "bin", "nethack.dll"),
			os.path.join(GAME, "mods", "nhv", "nhdata")]
	missing = [p for p in need if not os.path.exists(p)]
	if missing:
		sys.exit("not built (run tools/deploy.sh first): " + ", ".join(missing))


def stage(out):
	engine = os.path.join(out, "engine")
	# the program and its libraries
	os.makedirs(os.path.join(engine, "bin"))
	for f in os.listdir(os.path.join(LUANTI, "bin")):
		if f.lower().endswith((".exe", ".dll")):
			shutil.copy2(os.path.join(LUANTI, "bin", f), os.path.join(engine, "bin", f))
	for d in ENGINE_DIRS:
		copytree(os.path.join(LUANTI, d), os.path.join(engine, d))
	# the game
	copytree(GAME, os.path.join(engine, "games", "nethackvoxel"),
			lambda _d, names: [n for n in names if skip(n)])
	for f in MOD_DATA:
		src = os.path.join(LUANTI, "mod_data", "nhv", f)
		if os.path.exists(src):
			os.makedirs(os.path.join(engine, "mod_data", "nhv"), exist_ok=True)
			shutil.copy2(src, os.path.join(engine, "mod_data", "nhv", f))
	# an empty world for the game, and fresh settings
	write(os.path.join(engine, "worlds", "nethack", "world.mt"), WORLD_MT, crlf=False)
	write(os.path.join(engine, "minetest.conf"), CONF, crlf=False)
	# launchers
	os.makedirs(os.path.join(out, "Launchers"))
	for f in LAUNCHERS:
		shutil.copy2(os.path.join(ROOT, "Launchers", f), os.path.join(out, "Launchers", f))
	shutil.copy2(os.path.join(ROOT, "Launchers", RESET[0]), os.path.join(out, "Launchers", RESET[1]))
	shutil.copy2(os.path.join(ROOT, "Create Play Shortcut.bat"), out)
	write(os.path.join(out, "README.txt"), README)
	# licenses
	lic = os.path.join(out, "licenses")
	os.makedirs(lic)
	shutil.copy2(os.path.join(ROOT, "external", "nethack", "dat", "license"),
			os.path.join(lic, "NetHack-license.txt"))
	shutil.copy2(os.path.join(LUANTI, "LICENSE.txt"), os.path.join(lic, "Luanti-LICENSE.txt"))
	shutil.copy2(os.path.join(LUANTI, "COPYING.LESSER"), os.path.join(lic, "Luanti-COPYING.LESSER.txt"))
	sf = os.path.join(GAME, "mods", "nhv_sounds", "soundfonts", "GeneralUser-GS-LICENSE.txt")
	if os.path.exists(sf):
		shutil.copy2(sf, os.path.join(lic, "GeneralUser-GS-LICENSE.txt"))


def main():
	check_built()
	keep = "--keep" in sys.argv
	name = "NetHackVoxel-%s-%s" % (datetime.date.today().isoformat(), commit())
	stage_dir = os.path.join(DIST, name)
	if os.path.exists(stage_dir):
		shutil.rmtree(stage_dir)
	out = os.path.join(stage_dir, TOP)
	os.makedirs(out)
	stage(out)

	zpath = os.path.join(DIST, name + ".zip")
	with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
		for d, _dirs, files in os.walk(out):
			for f in files:
				p = os.path.join(d, f)
				z.write(p, os.path.relpath(p, stage_dir))
	if not keep:
		shutil.rmtree(stage_dir)
	print("%s (%.1f MB)" % (zpath, os.path.getsize(zpath) / 1e6))


if __name__ == "__main__":
	main()
