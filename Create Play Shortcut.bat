@echo off
rem Makes a "Play VoxHack" shortcut in this folder (and on the Desktop if
rem you like). Run it again if you move the folder.
choice /C YN /M "Also put a shortcut on the Desktop"
if errorlevel 2 (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Launchers\make_shortcut.ps1"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Launchers\make_shortcut.ps1" -Desktop
)
pause
