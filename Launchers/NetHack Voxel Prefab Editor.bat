@echo off
rem Opens the prefab editor world (creative). Cells save automatically as you build.
rem (the game is in ..\engine in a release, ..\external\luanti in the source tree)
set "ENGINE=%~dp0..\engine"
if not exist "%ENGINE%\bin\luanti.exe" set "ENGINE=%~dp0..\external\luanti"
cd /d "%ENGINE%"
rem (player names can't have spaces)
set "NAME=%USERNAME: =_%"
if not exist worlds\prefab_editor mkdir worlds\prefab_editor
if not exist worlds\prefab_editor\world.mt (
  echo gameid = nethackvoxel> worlds\prefab_editor\world.mt
  echo backend = sqlite3>> worlds\prefab_editor\world.mt
  echo player_backend = sqlite3>> worlds\prefab_editor\world.mt
  echo auth_backend = sqlite3>> worlds\prefab_editor\world.mt
  echo mod_storage_backend = sqlite3>> worlds\prefab_editor\world.mt
)
if not exist worlds\prefab_editor\nhv_editor type nul > worlds\prefab_editor\nhv_editor
start "" bin\luanti.exe --go --world worlds\prefab_editor --name %NAME% --password ""
