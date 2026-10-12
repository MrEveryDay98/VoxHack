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
| Right click (tap) | The obvious action for what you point at: open/close a door, take stairs, pick up, drink from a fountain, chat with a peaceful monster. |
| Right click (hold) | Action wheel for what you point at. Move the mouse toward an action and let go. Let go in the middle to cancel. |
| E (tap / hold) | The same, for the selected hotbar item. |
| Q | Drop the selected hotbar item. |
| Space | Wait/search one turn. |
| I | Inventory, with equipment slots: click a filled slot for its actions, or an empty one to equip something. |
| Z | Toggle the large overhead pixel map. |

Hotbar: slot 1 is the wielded weapon, slot 2 the alternate weapon, slot 3 is a spacer, then the rest of the inventory.

Direction prompts (zap, throw, apply, digâ€¦) are answered automatically with where you are
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
- **Monster size:** in the editor world, press E for the monster editor:
  - every monster and feature (tree, fountain, throne, sink, grave, altar) is listed, with a
    live turning preview on a 1-node grid (the bright 3×3 square is one map square);
  - a scale slider, "reset to default", and a hitbox toggle;
  - scales are saved for all worlds right away;
  - in game, `/scale <factor> <monster name>` does the same.
- Trees and furniture are extruded sprites. Trees also have an invisible collision box filling
  their square, because NetHack treats trees as solid.
- Boulders are solid; walking into one tries to push it. Messages about bumping into things are
  hidden.
- Each monster and feature can stand on the floor or hang from the ceiling, with an offset (set in
  the monster editor). Monsters face you; only items spin.
- Your body is never teleported for blocked moves; if NetHack refuses a square, it quietly
  retries until the square is free.

## Projectiles
- **Monster missiles** (arrows, daggers, spears, venom, potions) fly through the world instead
  of resolving on the grid.
  - They move at game-time speed, so they crawl while you stand still and you can step aside.
  - If one reaches your body, NetHack still rolls to hit; a miss shows a rising "Dodged!" and
    the missile flies on.
  - Missiles also hit monsters in their path, and drop where they stop.
- **Archers** and other ranged attackers keep 2.5–4.5 squares away. They can shoot from any
  angle with a clear line of sight, not only the eight grid directions.
- **Containers and corpses:** chests, large boxes and ice boxes face you instead of spinning;
  corpses lie flat.

## Sprites (moddable)
All sprites and tile textures come from one sprite sheet:
`game/nethackvoxel/mods/nhv_tiles/textures/nhv_tiles.png`.

- **Layout:** 48 sprites per row, 16×16 each, numbered from 0 left to right, top to bottom.
  It holds NetHack's original pixels, drop shadows included. Edit them however you like.
- **Male/female:** a monster's male and female tiles share one sprite when they look the same;
  pairs that differ have one each.
- **Statues:** they aren't in the sheet. The game draws the monster's sprite through a stone colour
  filter (`nhv_tiles.STONE` in `mods/nhv_tiles/init.lua`).
- **`mods/nhv_tiles/tilenames.lua`** lists:
  - what is at each sheet position (`sheet_names`),
  - which sheet position each NetHack tile uses (`sheet`),
  - which tiles are statues.
- **Editing:** changes show up the next time the game starts. The sheet is only generated when
  it's missing (delete it and run the deploy script to start over).

## Architecture
- `nhcore/`: NetHack 3.7 built as `nethack.dll` with a C API (`nhv_api.h`). NetHack runs on its
  own thread; a custom window port turns its output into events and blocks for input.
- `external/luanti` (branch `nhv`): exposes the API to Lua as `core.nh_*`
  (`src/script/lua_api/l_nethack.cpp`).
- `game/nethackvoxel`: the Luanti game.
  - `nh.lua`: drives NetHack.
  - `terrain.lua`: map â†’ nodes.
  - `mobs.lua`: sprites and tweening.
  - `player.lua`: free movement â†’ NetHack moves.
  - `hud.lua`, `ui.lua`, `actions.lua`: interface and controls.
- `tools/tiles2png.py`: vanilla tileset â†’ textures (each shown as an extruded voxel sprite).

## Verified so far
New game with NetHack's role menus; walking (time frozen while standing still); doors block;
melee kills; pet follows; inventory and item menus; y/n prompts; save on close and restore.

## Not yet verified or not built
- **Projectiles:** only thrown and shot missiles fly physically (arrows, daggers, spit venom,
  potions). Wand zaps and breath weapons still resolve on NetHack's grid.
- Monsters following the green path markers.
- Level changes (stairs) are coded but untested.
- Death and end screens are coded but untested.
- Not yet tested: hallucination and invisible-monster wobble, and blindness fog.
- Missing: animated projectiles and zaps (thrown objects just appear where they land), and
  smooth animation during multi-turn actions.
- Monsters can't be seen through doorways until NetHack reveals them (by design: the hero's
  view).
- Main menu still shows Luanti's stock UI.
