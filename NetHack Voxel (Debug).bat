@echo off
rem NetHack Voxel in debug (wizard) mode: its own world and character ("wizard"),
rem separate from your normal game. Debug commands: T, then e.g. wizwish, wizmap, wizgenesis.
cd /d "%~dp0external\luanti"
if not exist worlds\nethack_debug mkdir worlds\nethack_debug
if not exist worlds\nethack_debug\world.mt (
  echo gameid = nethackvoxel> worlds\nethack_debug\world.mt
  echo backend = sqlite3>> worlds\nethack_debug\world.mt
  echo player_backend = sqlite3>> worlds\nethack_debug\world.mt
  echo auth_backend = sqlite3>> worlds\nethack_debug\world.mt
  echo mod_storage_backend = sqlite3>> worlds\nethack_debug\world.mt
)
if not exist worlds\nethack_debug\nhv_debug type nul > worlds\nethack_debug\nhv_debug
start "" bin\luanti.exe --go --world worlds\nethack_debug --name wizard --password ""
