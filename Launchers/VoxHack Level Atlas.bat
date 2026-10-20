@echo off
rem The level atlas: every level of a game with the seed you choose, built
rem side by side (terrain only) to see how the prefabs fit together.
rem Same seed, same dungeon. Inside: K fly, H noclip, /atlas lists the levels,
rem /atlas <number> goes to one, /atlas ceilings takes the ceilings off.
rem (the game is in ..\engine in a release, ..\external\luanti in the source tree)
setlocal
set "ENGINE=%~dp0..\engine"
if not exist "%ENGINE%\bin\luanti.exe" set "ENGINE=%~dp0..\external\luanti"
cd /d "%ENGINE%"
rem (player names can't have spaces)
set "NAME=%USERNAME: =_%"

:ask
set "SEED="
set /p "SEED=Seed (any whole number above 0, e.g. 4242; nothing to cancel): "
if "%SEED%"=="" exit /b 0
rem (digits only)
echo %SEED%| findstr /r /x "[0-9][0-9]*" >nul || (
    echo That's not a whole number.
    goto ask
)
if "%SEED%"=="0" goto ask
set "WORLD=worlds\atlas_%SEED%"

if exist "%WORLD%\world.mt" (
    choice /C NY /M "The atlas for seed %SEED% is already built. Build it again (after prefab changes)"
    if errorlevel 2 (
        tasklist /FI "IMAGENAME eq luanti.exe" 2>nul | find /I "luanti.exe" >nul
        if not errorlevel 1 (
            echo VoxHack is running. Close it first, then run this again.
            pause
            exit /b 1
        )
        rmdir /s /q "%WORLD%"
    )
)
if not exist "%WORLD%" mkdir "%WORLD%"
if not exist "%WORLD%\world.mt" (
  echo gameid = nethackvoxel> "%WORLD%\world.mt"
  echo backend = sqlite3>> "%WORLD%\world.mt"
  echo player_backend = sqlite3>> "%WORLD%\world.mt"
  echo auth_backend = sqlite3>> "%WORLD%\world.mt"
  echo mod_storage_backend = sqlite3>> "%WORLD%\world.mt"
)
if not exist "%WORLD%\nhv_atlas" echo %SEED%> "%WORLD%\nhv_atlas"
start "" bin\luanti.exe --go --world "%WORLD%" --name %NAME% --password ""
