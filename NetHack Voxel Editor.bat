@echo off
rem Opens the sound & voice editor in your browser. It stops by itself when the editor tab is closed.
cd /d "%~dp0"
python tools\sound_editor\server.py
