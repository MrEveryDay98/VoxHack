# NetHack Voxel: status

## How to play
Double-click `Play NetHack Voxel.bat` in the project folder. Closing the window saves the
game; launching again continues it. Dying shows the end screen with a New Game button.

To rebuild after code changes: `tools/clang64.sh 'sh tools/deploy.sh'`
(Lua-only changes need no rebuild: the game folder is linked into Luanti.)

## Controls
| Input | Action |
|---|---|
| WASD + mouse | Move freely. Time crawls (~12% speed) while you stand still and speeds up to full as you move. |
| Left click | Attack the monster within reach nearest your crosshair. Costs one action of time. |
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

## Free movement
Monsters and the hero move continuously and are not tied to the grid. NetHack still decides
everything and rolls every die. The grid is only used for map features and for monsters'
pathfinding when they can't see you.

- **Monsters** walk straight at you when they can see you. Out of sight, they path over the map
  toward where they think you are. Their bodies are solid and as big as their sprites.
- **Pets** follow you and fight hostiles within reach.
- **Time:**
  - Time runs at about 12% while you stand still and up to 100% as you walk.
  - Actions run time at full speed for as long as they take in NetHack: about 0.75 s per action.
  - Change the minimum with the `nhv_time_min` setting.
- **Monster size:** `/scale <factor> <monster name>`, e.g. `/scale 1.5 jackal`. `/scale` lists
  your settings.

## Prefab editor
Double-click `NetHack Voxel Prefab Editor.bat`. It's a creative world with one build cell per
terrain type and one per trap.

- **Controls:** I opens the block palette, K toggles flying. Placing never uses up blocks, and
  punching removes a block instantly.
- **The cell:**
  - Each cell is 3�3 blocks with 19 layers.
  - The orange markers show the floor and ceiling levels.
  - Below the floor there is room for pits and stairs going down; above the ceiling, for stairs going up.
- **Orientation:**
  - Walls and doors are built in one orientation and rotated to fit. The text at the top of the
    screen says which.
  - Corners join east and south; T-walls join west, east and south; door passages run north�south.
- **Markers:**
  - Red `nhv:trigger`: touching it takes the stairs/ladder.
  - Green `nhv:mpath`: the path monsters follow to it (stored, but not used yet).
  - Yellow `nhv:carve`: forces air (trap overlays only).
  - All three are invisible in the game.
- **Commands:**
  - `/prefab save` saves every cell. Every game world uses the saved cells.
  - `/prefab reset <slot>`, `/prefab goto <slot>`, `/prefab list`.
- **Sprites:** a fountain, altar, trap etc. you build replaces its sprite.

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
- Dodgeable projectiles, plus a "Dodged!" text when NetHack's roll misses (next).
- Monsters following the green path markers.
- Level changes (stairs) are coded but untested.
- Death and end screens are coded but untested.
- Not yet tested: hallucination and invisible-monster wobble, and blindness fog.
- Missing: animated projectiles and zaps (thrown objects just appear where they land), and
  smooth animation during multi-turn actions.
- Monsters can't be seen through doorways until NetHack reveals them (by design: the hero's
  view).
- Main menu still shows Luanti's stock UI.
