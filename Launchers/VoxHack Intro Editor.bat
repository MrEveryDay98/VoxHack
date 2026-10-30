@echo off
rem Opens the intro editor world: the opening's forest (x, z 0 to 255), where
rem you put down the camera's way through it, signs and figures. Inside:
rem /intro_play plays it, /intro_save saves it for the game. Made the first
rem time (Luanti's world generator: rolling grass, NetHack's trees); delete
rem worlds\intro_editor for a new forest.
rem (the game is in ..\engine in a release, ..\external\luanti in the source tree)
set "ENGINE=%~dp0..\engine"
if not exist "%ENGINE%\bin\luanti.exe" set "ENGINE=%~dp0..\external\luanti"
cd /d "%ENGINE%"
rem (player names can't have spaces)
set "NAME=%USERNAME: =_%"
set "WORLD=worlds\intro_editor"
if not exist "%WORLD%" mkdir "%WORLD%"
if not exist "%WORLD%\world.mt" (
  echo gameid = nethackvoxel> "%WORLD%\world.mt"
  echo backend = sqlite3>> "%WORLD%\world.mt"
  echo player_backend = sqlite3>> "%WORLD%\world.mt"
  echo auth_backend = sqlite3>> "%WORLD%\world.mt"
  echo mod_storage_backend = sqlite3>> "%WORLD%\world.mt"
)
rem (the world generator's settings: low rolling hills, no caves, mountains
rem or water - tools\make_intro_world.py has the same)
if not exist "%WORLD%\map_meta.txt" (
  echo mg_name = v7> "%WORLD%\map_meta.txt"
  echo seed = 2207>> "%WORLD%\map_meta.txt"
  echo water_level = -64>> "%WORLD%\map_meta.txt"
  echo mg_flags = nocaves, nodungeons, light, decorations, biomes, noores>> "%WORLD%\map_meta.txt"
  echo mgv7_spflags = nomountains, noridges, nofloatlands, nocaverns>> "%WORLD%\map_meta.txt"
  echo [end_of_params]>> "%WORLD%\map_meta.txt"
)
if not exist "%WORLD%\nhv_intro" type nul > "%WORLD%\nhv_intro"
start "" bin\luanti.exe --go --world %WORLD% --name %NAME% --password ""
