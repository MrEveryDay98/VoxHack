@echo off
rem Launches VoxHack straight into the game (world: worlds\nethack in the game folder).
rem (the game is in ..\engine in a release, ..\external\luanti in the source tree)
set "ENGINE=%~dp0..\engine"
if not exist "%ENGINE%\bin\luanti.exe" set "ENGINE=%~dp0..\external\luanti"
cd /d "%ENGINE%"
rem (player names can't have spaces)
set "NAME=%USERNAME: =_%"
start "" bin\luanti.exe --go --world worlds\nethack --name %NAME% --password ""
