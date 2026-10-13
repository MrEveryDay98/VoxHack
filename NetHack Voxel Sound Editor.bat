@echo off
rem Opens the sound & voice editor in your browser (close this window to stop it).
cd /d "%~dp0"
python tools\sound_editor\server.py
