@echo off
rem Launches NetHack Voxel straight into the game (world: external\luanti\worlds\nethack).
cd /d "%~dp0external\luanti"
start "" bin\luanti.exe --go --world worlds\nethack --name %USERNAME% --password ""
