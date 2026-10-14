@echo off
rem Deletes the saved NetHack game(s) in the main world (worlds\nethack), so
rem the next "Play NetHack Voxel" starts a new character. For testing.
rem Keeps the high scores / game log and the game's own settings file.
setlocal
rem (the game is in ..\engine in a release, ..\external\luanti in the source tree)
set "ENGINE=%~dp0..\engine"
if not exist "%ENGINE%\bin\luanti.exe" set "ENGINE=%~dp0..\external\luanti"
set "SAVES=%ENGINE%\worlds\nethack\nethack"

tasklist /FI "IMAGENAME eq luanti.exe" 2>nul | find /I "luanti.exe" >nul
if not errorlevel 1 (
    echo NetHack Voxel is still running. Close the game first, then run this again.
    pause
    exit /b 1
)

if not exist "%SAVES%" (
    echo No saves found ^(%SAVES% doesn't exist^).
    pause
    exit /b 0
)

echo This deletes your saved NetHack game^(s^) in:
echo   %SAVES%
choice /C YN /M "Delete them"
if errorlevel 2 (
    echo Nothing deleted.
    pause
    exit /b 0
)

pushd "%SAVES%"
set COUNT=0
rem saved games
for %%f in (*.NetHack-saved-game) do (
    del /q "%%f" && set /a COUNT+=1 >nul
)
rem a game in progress: <name>.0, <name>.1, ... (one file per level)
for %%f in (*) do (
    echo %%~xf| findstr /r /x "\.[0-9][0-9]*" >nul && (
        del /q "%%f" && set /a COUNT+=1 >nul
    )
)
popd

echo Deleted %COUNT% file^(s^). The next game starts a new character.
pause
