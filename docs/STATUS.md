# NetHack Voxel: status

## How to play
Double-click `Play NetHack Voxel.bat` in the project folder. Closing the window saves the
game; launching again continues it. Dying shows the end screen with a New Game button.

To rebuild after code changes: `tools/clang64.sh 'sh tools/deploy.sh'`
(Lua-only changes need no rebuild: the game folder is linked into Luanti.)

## Controls
| Input | Action |
|---|---|
| WASD + mouse | Move freely. Time passes only while you move or act. One square walked = one turn. |
| Left click | Attack the adjacent monster nearest your crosshair (NetHack `F` + direction). |
| Shift + left click | Fire quivered ammo where you look. |
| Right click | Context action: open/close a door, take the stairs you stand on, pick up items, chat. |
| Shift + right click | Menu of everything you can do at the square you're looking at. |
| E | Action menu for the selected hotbar item. |
| Q | Drop the selected hotbar item. |
| Space | Wait/search one turn. |
| I | Inventory (click an item for its action menu). |
| Z | Toggle the large overhead pixel map. |

Direction prompts (zap, throw, apply, dig…) are answered automatically with where you are
looking: look steeply down for `>` (down), up for `<`.

## Architecture
- `nhcore/`: NetHack 3.7 built as `nethack.dll` with a C API (`nhv_api.h`). NetHack runs on its
  own thread; a custom window port turns its output into events and blocks for input.
- `external/luanti` (branch `nhv`): exposes the API to Lua as `core.nh_*`
  (`src/script/lua_api/l_nethack.cpp`).
- `game/nethackvoxel`: the Luanti game.
  - `nh.lua`: drives NetHack.
  - `terrain.lua`: map → nodes.
  - `mobs.lua`: sprites and tweening.
  - `player.lua`: free movement → NetHack moves.
  - `hud.lua`, `ui.lua`, `actions.lua`: interface and controls.
- `tools/tiles2png.py`: vanilla tileset → textures (each shown as an extruded voxel sprite).

## Verified so far
New game with NetHack's role menus; walking (time frozen while standing still); doors block;
melee kills; pet follows; inventory and item menus; y/n prompts; save on close and restore.

## Not yet verified or not built
- Level changes (stairs) are coded but untested.
- Death and end screens are coded but untested.
- Not yet tested: hallucination and invisible-monster wobble, and blindness fog.
- Missing: animated projectiles and zaps (thrown objects just appear where they land), and
  smooth animation during multi-turn actions.
- Monsters can't be seen through doorways until NetHack reveals them (by design: the hero's
  view).
- Main menu still shows Luanti's stock UI.
