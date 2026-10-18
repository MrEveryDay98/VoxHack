#!/bin/sh
# Syntax-check every Lua file of the game (run in CLANG64: needs luajit),
# and catch globals that aren't meant to be there - a typo'd or missing
# local reads a global (nil) instead of failing to compile.
cd "$(dirname "$0")/.." || exit 1
ok=0
# the globals the game may use: Lua's, Luanti's, and the game's own tables
ALLOWED=" core nhv nhv_tiles vector VoxelArea ItemStack DIR_DELIM dofile math table string io os \
ipairs pairs next type tonumber tostring setmetatable getmetatable rawget rawset select \
unpack error assert pcall xpcall print loadstring "
for f in game/nethackvoxel/mods/*/*.lua; do
	luajit -bl "$f" > /tmp/luabc.txt 2> /tmp/luaerr.txt || { cat /tmp/luaerr.txt; ok=1; continue; }
	for g in $(grep -oE "G(GET|SET) .*; \"[A-Za-z_0-9]+\"" /tmp/luabc.txt | sed -E "s/.*\"([A-Za-z_0-9]+)\"/\1/" | sort -u); do
		case "$ALLOWED" in
		*" $g "*) ;;
		*) echo "$f: unknown global '$g'"; ok=1 ;;
		esac
	done
done
exit $ok
