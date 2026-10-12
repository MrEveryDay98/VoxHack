# NetHack Voxel: status

## Done
- `nhcore/`: NetHack 3.7 builds as `nethack.dll` (clang64 + CMake) with a C API (`nhv_api.h`).
  The headless harness `nhvtest` covers new game, moving, inventory menus, saving and restoring.
- `external/luanti` (branch `nhv`): exposes the API to Lua as `core.nh_*` (`src/script/lua_api/l_nethack.cpp`). Builds cleanly.
- `tools/tiles2png.py`: vanilla tileset converted to 2304 PNGs, which become extruded-voxel items in the `nhv_tiles` mod.
- `game/nethackvoxel/mods/nhv`: written but not yet run: `util.lua`, `terrain.lua`, `nh.lua`,
  `mobs.lua`, `player.lua`.

## Next
1. `hud.lua` (status, messages, overhead pixel map), `ui.lua` (yn/menu/line prompts, inventory and
   item context menus, hotbar mirror), `actions.lua` (aimed attack, interact, item actions,
   auto-answering direction prompts from look direction), `init.lua` (load order, world emerge,
   start the game on join), `mod.conf`.
2. Deploy script: copy `nethack.dll` to `luanti/bin`, `nhdata` to `mods/nhv/nhdata`, and link the game into `luanti/games`.
3. First in-game test pass.
4. Later: blindness fog, hallucination effects, digging, Sokoban map polish, death screen, main menu cleanup.

## Build
- tools/clang64.sh 'cmake -S nhcore -B build/nhcore -G Ninja && ninja -C build/nhcore'
- tools/clang64.sh 'cd external/luanti && ninja -C build'
