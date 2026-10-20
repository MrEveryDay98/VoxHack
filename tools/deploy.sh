#!/bin/sh
# Build everything and assemble a runnable game inside external/luanti.
# Run from an MSYS2 CLANG64 shell, or via: tools/clang64.sh tools/deploy.sh
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
LUANTI=$ROOT/external/luanti
GAME=$ROOT/game/nethackvoxel

# 1. NetHack library + data
[ -f "$ROOT/build/nhcore/build.ninja" ] || cmake -S "$ROOT/nhcore" -B "$ROOT/build/nhcore" -G Ninja -DCMAKE_BUILD_TYPE=Release
ninja -C "$ROOT/build/nhcore"

# 2. Luanti
[ -f "$LUANTI/build/build.ninja" ] || cmake -S "$LUANTI" -B "$LUANTI/build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DRUN_IN_PLACE=TRUE -DBUILD_UNITTESTS=FALSE
ninja -C "$LUANTI/build"

# 2b. samtool.exe for the sound editor's SAM previews: the engine's own SAM
# code (lib/sam through sam_unity.c, and sam_speech.cpp), so they match
SND="$LUANTI/src/client/sound"
TOOL="$ROOT/build/sam/samtool.exe"
if [ ! -f "$TOOL" ] || [ -n "$(find "$LUANTI/lib/sam" "$SND"/sam_* "$ROOT/tools/samtool.cpp" -newer "$TOOL" -name '*.[ch]*')" ]; then
	mkdir -p "$ROOT/build/sam"
	clang -Os -w -I"$LUANTI/lib/sam" -c -o "$ROOT/build/sam/sam_unity.o" "$SND/sam_unity.c"
	clang++ -O2 -std=c++17 -static -I"$SND" -o "$TOOL" "$ROOT/tools/samtool.cpp" "$SND/sam_speech.cpp" \
		"$ROOT/build/sam/sam_unity.o"
fi

# 3. tiles
if [ ! -f "$GAME/mods/nhv_tiles/textures/nhv_tiles.png" ]; then
	python -I "$ROOT/tools/tiles2png.py" "$ROOT/external/nethack" "$GAME/mods/nhv_tiles/textures" "$GAME/mods/nhv_tiles/tilenames.lua"
fi
# seamless wall textures (only the missing ones are made; edit them freely)
python -I "$ROOT/tools/make_wall_textures.py" "$GAME/mods/nhv_tiles/textures"

# 4. assemble
cp "$ROOT/build/nhcore/nethack.dll" "$LUANTI/bin/"
rm -rf "$GAME/mods/nhv/nhdata"
cp -r "$ROOT/build/nhcore/nhdata" "$GAME/mods/nhv/nhdata"
# the editors' data (prefabs, areas, sizes) lives in the repository's mod_data;
# the engine reads and writes it through a link
if [ ! -e "$LUANTI/mod_data" ]; then
	/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -Command "New-Item -ItemType Junction -Path '$(cygpath -w "$LUANTI/mod_data")' -Target '$(cygpath -w "$ROOT/mod_data")'" > /dev/null
fi
if [ ! -e "$LUANTI/games/nethackvoxel" ]; then
	/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -Command "New-Item -ItemType Junction -Path '$(cygpath -w "$LUANTI/games/nethackvoxel")' -Target '$(cygpath -w "$GAME")'" > /dev/null
fi
mkdir -p "$LUANTI/worlds/nethack"
[ -f "$LUANTI/worlds/nethack/world.mt" ] || printf 'gameid = nethackvoxel\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$LUANTI/worlds/nethack/world.mt"
(cd "$LUANTI/build" && sh ../util/bundle_dlls.sh ../bin/luanti.exe ../bin/ > /dev/null)
echo "deployed: $LUANTI/bin/luanti.exe --go --world worlds/nethack"
