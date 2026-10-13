@echo off
rem Opens the NetHack Voxel editor on its Blocks tab (blocks for prefabs). It stops by itself when the editor tab is closed.
cd /d "%~dp0"
python tools\sound_editor\server.py --blocks
