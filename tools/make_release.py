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
CREDITS.txt lists what the game is made of and under which licence. The
licenses folder has the licence texts: NetHack (NetHack General Public
License), Luanti (LGPL 2.1+), the GeneralUser GS SoundFont, TinySoundFont,
and every bundled library (THIRD-PARTY.txt lists them).
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
	# the special level areas built in the editor (/area)
	areas_dir = os.path.join(LUANTI, "mod_data", "nhv", "areas")
	if os.path.isdir(areas_dir):
		copytree(areas_dir, os.path.join(engine, "mod_data", "nhv", "areas"))
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
	shutil.copy2(os.path.join(LUANTI, "src", "client", "sound", "tinysoundfont", "LICENSE.txt"),
			os.path.join(lic, "TinySoundFont-LICENSE.txt"))
	shutil.copy2(os.path.join(ROOT, "CREDITS.md"), os.path.join(out, "CREDITS.txt"))
	libraries(engine, lic)


# The libraries shipped as DLLs (built by MSYS2 CLANG64): DLL -> package (its
# licence files are in clang64/share/licenses/<package>), licence, project.
# Extra licence texts the packages don't install are in tools/licenses.
MSYS_LICENSES = r"C:\msys64\clang64\share\licenses"
DLLS = {
	"SDL2.dll": ("SDL2", "Zlib", "https://www.libsdl.org/"),
	"libbrotlicommon.dll": ("brotli", "MIT", "https://github.com/google/brotli"),
	"libbrotlidec.dll": ("brotli", "MIT", "https://github.com/google/brotli"),
	"libbz2-1.dll": ("bzip2", "bzip2 (BSD-style)", "https://sourceware.org/bzip2/"),
	"libc++.dll": ("libc++", "Apache-2.0 WITH LLVM-exception", "https://libcxx.llvm.org/"),
	"libcrypto-3-x64.dll": ("openssl", "Apache-2.0", "https://www.openssl.org/"),
	"libcurl-4.dll": ("curl", "curl (MIT-style)", "https://curl.se/"),
	"libfreetype-6.dll": ("freetype", "FreeType License (FTL), chosen of FTL / GPL-2.0",
		"https://freetype.org/"),
	"libglib-2.0-0.dll": ("glib2", "LGPL-2.1-or-later", "https://gitlab.gnome.org/GNOME/glib"),
	"libgmp-10.dll": ("gmp", "LGPL-3.0-or-later (chosen of LGPL-3.0 / GPL-2.0)", "https://gmplib.org/"),
	"libgraphite2.dll": ("graphite2", "LGPL-2.1-or-later", "https://github.com/silnrsi/graphite"),
	"libharfbuzz-0.dll": ("harfbuzz", "MIT", "https://harfbuzz.github.io/"),
	"libiconv-2.dll": ("libiconv", "LGPL-2.1-or-later", "https://www.gnu.org/software/libiconv/"),
	"libidn2-0.dll": ("libidn2", "LGPL-3.0-or-later (chosen of LGPL-3.0 / GPL-2.0)",
		"https://www.gnu.org/software/libidn/#libidn2"),
	"libintl-8.dll": ("gettext-runtime", "LGPL-2.1-or-later", "https://www.gnu.org/software/gettext/"),
	"libjpeg-8.dll": ("libjpeg-turbo", "IJG / BSD-3-Clause / Zlib", "https://libjpeg-turbo.org/"),
	"libjsoncpp-27.dll": ("jsoncpp", "MIT", "https://github.com/open-source-parsers/jsoncpp"),
	"liblzma-5.dll": ("xz", "0BSD", "https://tukaani.org/xz/"),
	"libogg-0.dll": ("libogg", "BSD-3-Clause", "https://xiph.org/ogg/"),
	"libopenal-1.dll": ("openal", "LGPL-2.0-or-later (GNU Library GPL v2)",
		"https://github.com/kcat/openal-soft"),
	"libpcre2-8-0.dll": ("pcre2", "BSD-3-Clause", "https://pcre2project.github.io/pcre2/"),
	"libpng16-16.dll": ("libpng", "libpng (PNG Reference Library License)", "http://www.libpng.org/"),
	"libpsl-5.dll": ("libpsl", "MIT", "https://github.com/rockdaboot/libpsl"),
	"libsqlite3-0.dll": ("sqlite3", "Public domain", "https://www.sqlite.org/"),
	"libssh2-1.dll": ("libssh2", "BSD-3-Clause", "https://libssh2.org/"),
	"libunistring-5.dll": ("libunistring", "LGPL-3.0-or-later (chosen of LGPL-3.0 / GPL-2.0)",
		"https://www.gnu.org/software/libunistring/"),
	"libvorbis-0.dll": ("libvorbis", "BSD-3-Clause", "https://xiph.org/vorbis/"),
	"libvorbisfile-3.dll": ("libvorbis", "BSD-3-Clause", "https://xiph.org/vorbis/"),
	"libzip.dll": ("libzip", "BSD-3-Clause", "https://libzip.org/"),
	"libzstd.dll": ("zstd", "BSD-3-Clause (chosen of BSD-3-Clause / GPL-2.0)",
		"https://facebook.github.io/zstd/"),
	"lua51.dll": ("luajit", "MIT", "https://luajit.org/"),
	"zlib1.dll": ("zlib", "Zlib", "https://zlib.net/"),
}
# licence texts the packages above don't install (from the projects themselves)
EXTRA = {
	"openal": ["openal-soft-COPYING.txt"],
	"luajit": ["luajit-COPYRIGHT.txt"],
	"libvorbis": ["libvorbis-COPYING.txt"],
	"gmp": ["lgpl-3.0.txt", "gpl-3.0.txt"],
	"libidn2": ["lgpl-3.0.txt", "gpl-3.0.txt"],
}


def libraries(engine, lic):
	libdir = os.path.join(lic, "libraries")
	os.makedirs(libdir, exist_ok=True)
	lines = ["Libraries shipped in engine\\bin (built with MSYS2 CLANG64)",
		"Their licence texts are in licenses\\libraries\\<package>.",
		"The source code of each is available from its project (below) and from",
		"MSYS2 (https://packages.msys2.org/, package mingw-w64-clang-x86_64-<package>).",
		""]
	shipped = set(f for f in os.listdir(os.path.join(engine, "bin")) if f.lower().endswith(".dll"))
	unknown = sorted(shipped - set(DLLS) - {"nethack.dll"})
	if unknown:
		sys.exit("no licence information for: " + ", ".join(unknown) + " (add them to DLLS)")
	for dll in sorted(shipped - {"nethack.dll"}):
		pkg, licence, url = DLLS[dll]
		lines.append("%-22s %-16s %s  %s" % (dll, pkg, licence, url))
		dst = os.path.join(libdir, pkg)
		if not os.path.isdir(dst):
			src = os.path.join(MSYS_LICENSES, pkg)
			if os.path.isdir(src):
				copytree(src, dst)
			for f in EXTRA.get(pkg, []):
				os.makedirs(dst, exist_ok=True)
				shutil.copy2(os.path.join(ROOT, "tools", "licenses", f), os.path.join(dst, f))
			if not (os.path.isdir(dst) and os.listdir(dst)):
				sys.exit("no licence text found for " + pkg)
	lines += ["", "Built into luanti.exe: Luanti (LGPL-2.1-or-later) with IrrlichtMt and the",
		"libraries listed in Luanti-LICENSE.txt; TinySoundFont (MIT, TinySoundFont-LICENSE.txt).",
		"nethack.dll: NetHack 3.7 (NetHack General Public License, NetHack-license.txt).",
		"Fonts in engine\\fonts: Arimo, Cousine (Apache-2.0), Droid Sans Fallback",
		"(Apache-2.0); their licence files are next to them."]
	write(os.path.join(lic, "THIRD-PARTY.txt"), "\n".join(lines) + "\n")


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
