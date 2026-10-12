#!/bin/sh
# Syntax-check every Lua file of the game (run in CLANG64: needs luajit).
cd "$(dirname "$0")/.." || exit 1
ok=0
for f in game/nethackvoxel/mods/*/*.lua; do
	luajit -bl "$f" > /dev/null 2> /tmp/luaerr.txt || { cat /tmp/luaerr.txt; ok=1; }
done
exit $ok
