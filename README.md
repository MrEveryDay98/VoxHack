# VoxHack

**NetHack 3.7 in first person, in a voxel world.** Based on NetHack, running on a
modified [Luanti](https://www.luanti.org/) engine. Windows only.

**Website:** https://mreveryday98.github.io/VoxHack/ · **Download:** [latest release](../../releases/latest)

NetHack still decides everything: every rule, every die roll, every monster.
VoxHack is how you see it and move through it: walk the dungeon freely, look
around in 3D, swing at what's in front of you, and watch the Mazes of Menace
take shape around you.

- Free movement in a 3D dungeon built from NetHack's own levels
- Real-time-ish play: time crawls while you stand still and runs as you move
- Monsters as sprites from NetHack's tile set, walking, fighting and fleeing in 3D
- Mouse-driven actions: attack, fire, a right-click action wheel, an item hotbar
- NetHack's special levels hand-built as 3D areas (Sokoban, the Oracle, the Planes...)
- Sound effects, music and skies for each part of the dungeon

## Play

Download the latest zip from [Releases](../../releases), unpack it anywhere and
run **Create Play Shortcut.bat** (or `Launchers\Play VoxHack.bat`). Your game,
settings and high scores stay inside that folder.

| Input | Action |
|---|---|
| WASD + mouse | Move and look |
| Left click | Attack what's in reach under your crosshair |
| Shift + left click | Fire your quivered ammo where you look |
| Right click | Tap: the obvious action for what you point at (open a door, take the stairs, talk). Hold: an action wheel |
| Hold Shift, Ctrl, Alt, or E | Other wheel options |
| 1-5 | Fire, Kick, Zap, Spell, Eat |
| R | Pick up |
| X | Search (hold to keep searching) |
| I | Inventory and equipment |
| Z | The big overhead map |
| T | NetHack's command line (`#pray`, `20s`...) |

Look steeply down or up when zapping, digging or casting to aim down (`>`) or up (`<`).

## Build from source

You need Windows with [MSYS2](https://www.msys2.org/) (in `C:\msys64`) and Python 3
with Pillow.

1. In an MSYS2 shell, install the CLANG64 toolchain and libraries:

   ```sh
   pacman -S --needed git mingw-w64-clang-x86_64-{clang,cmake,ninja,SDL2,freetype,openal,libvorbis,curl,sqlite3,zstd,luajit,jsoncpp,gettext,gmp,libjpeg-turbo,libpng}
   ```

2. Clone with the two modified engines (NetHack and Luanti, branch `nhv`):

   ```sh
   git clone --recurse-submodules https://github.com/MrEveryDay98/VoxHack.git
   ```

3. Build and assemble the game (from the repository, in Git Bash or MSYS2):

   ```sh
   tools/clang64.sh 'sh tools/deploy.sh'
   ```

4. Play: `Launchers\Play VoxHack.bat`. To make a release zip:
   `python -I tools/make_release.py` (writes `dist/VoxHack-<date>-<commit>.zip`).

Lua changes in `game/nethackvoxel` need no rebuild: the game folder is linked
into the engine. More detail in [docs/STATUS.md](docs/STATUS.md).

### Layout

| Path | What |
|---|---|
| `game/nethackvoxel` | The game (Luanti mods, in Lua): the 3D world, controls, HUD, sound |
| `nhcore` | The bridge between NetHack and the engine (built into `nethack.dll`) |
| `external/nethack` | NetHack 3.7, modified (submodule, branch `nhv`) |
| `external/luanti` | Luanti, modified (submodule, branch `nhv`) |
| `tools` | Build, release and asset tools, and the sound/sky/block editor |

## Credits and licence

VoxHack is based on NetHack, by the NetHack DevTeam, and is not an official
NetHack release. It is distributed under the NetHack General Public License
(see [LICENSE](LICENSE)). Luanti is under the LGPL 2.1 or later. What every
part of the game is and where it comes from is in [CREDITS.md](CREDITS.md).
