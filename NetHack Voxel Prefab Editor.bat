@echo off
rem Opens the prefab editor world (creative). Cells save automatically as you build.
cd /d "%~dp0external\luanti"
if not exist worlds\prefab_editor mkdir worlds\prefab_editor
if not exist worlds\prefab_editor\world.mt (
  echo gameid = nethackvoxel> worlds\prefab_editor\world.mt
  echo backend = sqlite3>> worlds\prefab_editor\world.mt
  echo player_backend = sqlite3>> worlds\prefab_editor\world.mt
  echo auth_backend = sqlite3>> worlds\prefab_editor\world.mt
  echo mod_storage_backend = sqlite3>> worlds\prefab_editor\world.mt
)
if not exist worlds\prefab_editor\nhv_editor type nul > worlds\prefab_editor\nhv_editor
start "" bin\luanti.exe --go --world worlds\prefab_editor --name %USERNAME% --password ""
