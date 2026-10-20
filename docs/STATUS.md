# VoxHack: status

## How to play
Double-click `Launchers/Play VoxHack.bat` (or run `Create Play Shortcut.bat` once for a
shortcut). The other launchers (debug, editors, reset save) are in `Launchers/` too. Closing the window saves the
game; launching again continues it. Dying shows the end screen with a New Game button.

To rebuild after code changes: `tools/clang64.sh 'sh tools/deploy.sh'`
(Lua-only changes need no rebuild: the game folder is linked into Luanti.)

To make a release zip (no saves, editors or dev tools): build, then
`python -I tools/make_release.py` -> `dist/VoxHack-<date>-<commit>.zip`.

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
- **Wands, spells and breath** are ray projectiles, not grid lines.
  - Your own zaps go where you look; a monster's are aimed at your body.
  - They fly at game-time speed, reach up to NetHack's range in squares, and bounce off walls
    up to 2 times. Change these with the settings `nhv_ray_bounces` and `nhv_ray_range_scale`.
  - Each body a ray passes through gets NetHack's hit roll; reflection turns the ray around.
  - Every square it crosses still gets NetHack's effects (burning, freezing water and so on).
- **Combat flashes:** a monster flashes faintly white with a swipe when it attacks, and red when
  it is hurt.
- **Containers and corpses:** chests, large boxes and ice boxes face you instead of spinning;
  corpses lie flat.

## Runs as a local application
The VoxHack build of Luanti always plays a world on the command line in single-player
mode, keeping your name (NetHack saves go by it). Its built-in server and client sockets exist
only on 127.0.0.1, on ports the OS picks, so nothing is reachable from the network. The window
is titled "VoxHack"; the pause menu is Continue / Settings / Sound Volume / Quit, with no
server or version information; loading shows "Loading...".

## Graphics options
Inventory > Graphics (applies immediately, remembered):
- **Interface:** Retro (default) or Modern (setting `nhv_interface`). Retro uses NetHack's
  public-domain IBM PC pixel font (`mods/nhv/fonts/nhv_retro.ttf`, made from
  `external/nethack/win/X11/ibm.bdf` by `tools/make_pixel_font.py`; plain ASCII only, other
  characters come from the fallback font) at whole multiples of 14 px, and old-PC style boxes and
  buttons (`nhv_tiles/textures/nhv_ui_*.png`, from `tools/make_ui_textures.py`) given to every
  screen through the formspec prepend (`theme.lua`).
- **HUD size / Menu size:** Luanti's `hud_scaling` / `gui_scaling`. The VoxHack build of
  Luanti sizes HUD text by the HUD size (not the menu size) and rounds it down to the pixel font's
  steps, so labels stay inside their boxes.
- **Map size:** the corner map's pixels per square (`nhv_map_scale`, 0 hides it); the big map
  fits the window.
- **Sprites:** extruded voxel models, or flat sprites (setting `nhv_flat_sprites`).
- **Render resolution:** full down to 1/8. The world is drawn smaller and scaled up with sharp
  pixels for a retro look; the HUD and menus stay sharp (Luanti's `undersampling`, which the
  VoxHack build of Luanti now applies without a restart).
- **Distant textures:** sharp, or smoothed by mipmaps (setting `mip_map`). Turning it off applies
  at once; turning it back on may need a restart if the game started with it off.

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
- **Walls:** each NetHack wall set (main dungeon, Gnomish Mines, Gehennom, Fort Ludios, Sokoban)
  has a seamless texture, `nhv_wall_<set>.png`, made from its sprite by
  `tools/make_wall_textures.py`. Levels use their own set. Edit them freely; missing ones are
  remade on deploy.
- **Editing:** changes show up the next time the game starts. The sheet is only generated when
  it's missing (delete it and run the deploy script to start over).

## Sounds and voice lines
- **Sound editor:** run `Launchers/VoxHack Editor.bat` (sounds, voices and blocks). It opens a browser page where you
  assign sounds to hooks. Changes are picked up by a running game within about 2 seconds.
- **Hooks** are called from NetHack's code (`NHV_HOOK`), traps, NetHack's own sound effects,
  game events and music. They are not read from the message feed. The list is in
  `mods/nhv_sounds/catalog/hooks.json`; rebuild it with `tools/build_sound_catalog.py`.
- **Dialogue:** every spoken line, quest text and narration is listed and labelled in the editor
  (`catalog/dialogue.json`), ready for voice acting.
- **Sound library folders:** sounds can sit in folders under `sounds/` (the game loads them all).
  Whole folders can be imported. Names stay unique across folders because Luanti needs that.
- **Voice generation (Voice casting tab):** Kokoro text-to-speech, run locally (no account or
  credits). Choose a Kokoro voice per speaker (optionally a blend of two), its speed and accent,
  and an effect preset, then generate lines singly or in bulk.
  - "Install Kokoro" makes `voice_work/kokoro/` (a venv with kokoro-onnx, plus the ~120 MB model);
    `kokoro_worker.py` runs in it, so the editor itself still needs only Python and ffmpeg.
  - Quest placeholders are filled with each role's real names; parts that change per game (your
    name, god, gender) are read generically and flagged. Each line's spoken text can be edited.
  - Takes are kept in `voice_work/` (not in git). The preset's effects (pitch, filters, EQ, echo,
    reverb, chorus, distortion, bitcrush, robot, whisper...) are applied with ffmpeg, then every
    line is resampled to the global rate (11025 Hz by default), and the result goes to
    `sounds/voices/` once confirmed.
- **SAM, live (Voice casting > SAM view):** speakers ticked "Speak live with SAM" are voiced
  in the game by SAM (Software Automatic Mouth, 1982), built into the engine: `sound.lua`
  plays a sound named `nhv_sam:<speed>,<pitch>,<throat>,<mouth>,<sing>,<phonetic>|<text>`
  with the line's real text, and the client's sound manager synthesizes it
  (`src/client/sound/sam_voice.cpp`). Per speaker: a classic SAM voice or custom speed,
  pitch, throat and mouth, sing mode, volume; a line can pick another SAM voice.
  - SAM's C source (Sebastian Macke's port, no licence; included knowingly) is in
    `external/luanti/lib/sam`; `sam_unity.c` builds it into the engine with its globals
    renamed. `tools/deploy.sh` also builds `build/sam/sam.exe`, which the editor previews with.
  - Spoken lines are matched to the dialogue catalog by the most specific pattern; lines that
    are nearly all placeholders ("%s") are never matched.
- **Starting sounds:** imported from the YHACSIB sound bank as Ogg files (`tools/import_soundbank.py`).

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
- **Rays:** hitting monsters, reflection, and monster breath are coded but untested in game
  (the hero's wand of fire was tested: it flies, bounces and ends).
- Combat flashes, flowing water and sounds have not been checked in game yet.
- Monsters following the green path markers.
- Level changes (stairs) are coded but untested.
- Death and end screens are coded but untested.
- Not yet tested: hallucination and invisible-monster wobble, and blindness fog.
- Missing: animated projectiles and zaps (thrown objects just appear where they land), and
  smooth animation during multi-turn actions.
- Monsters can't be seen through doorways until NetHack reveals them (by design: the hero's
  view).
- Main menu still shows Luanti's stock UI.
