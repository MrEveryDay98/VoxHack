@echo off
rem NetHack Voxel Editor: sounds, music, voices and blocks, in your browser.
rem It stops by itself when the editor tab is closed.
cd /d "%~dp0.."
python tools\sound_editor\server.py
