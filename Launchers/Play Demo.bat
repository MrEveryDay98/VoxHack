@echo off
rem Plays a VoxHack demo back. Drop a .nhvdemo file onto this to play it;
rem run it on its own to play the newest demo you recorded (Options > Record
rem demos; they're kept in engine\demos - external\luanti\demos in the source
rem tree). Space pauses, W and S speed it up and slow it down, Esc leaves.
rem A demo plays only in the version of VoxHack that recorded it.
setlocal
rem (the game is in ..\engine in a release, ..\external\luanti in the source tree)
set "ENGINE=%~dp0..\engine"
if not exist "%ENGINE%\bin\luanti.exe" set "ENGINE=%~dp0..\external\luanti"
set "DEMO=%~1"
if "%DEMO%"=="" (
	for /f "delims=" %%f in ('dir /b /o-d "%ENGINE%\demos\*.nhvdemo" 2^>nul') do (
		if not defined DEMO set "DEMO=%ENGINE%\demos\%%f"
	)
)
if "%DEMO%"=="" (
	echo No demos recorded yet. Turn on Options ^> Record demos and play a game.
	pause
	exit /b 1
)
cd /d "%ENGINE%"
start "" bin\luanti.exe --go --nhv-demo "%DEMO%"
