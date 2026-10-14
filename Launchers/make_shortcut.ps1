# Makes a "Play NetHack Voxel" shortcut (run by "Create Play Shortcut.bat").
# The shortcut starts the game directly, with its icon; it goes next to the
# .bat, and on the Desktop too if you like.
param([switch]$Desktop)

$root = Split-Path -Parent $PSScriptRoot
# (the game is in engine\ in a release, external\luanti in the source tree)
$engine = Join-Path $root "engine"
if (-not (Test-Path (Join-Path $engine "bin\luanti.exe"))) {
	$engine = Join-Path $root "external\luanti"
}
$exe = Join-Path $engine "bin\luanti.exe"
if (-not (Test-Path $exe)) {
	Write-Host "Can't find the game (looked for engine\bin\luanti.exe)."
	exit 1
}

# player names: letters, digits, - and _ only
$name = ($env:USERNAME -replace '[^A-Za-z0-9_-]', '_')
if (-not $name) { $name = "player" }

$places = @($root)
if ($Desktop) { $places += [Environment]::GetFolderPath("Desktop") }

$shell = New-Object -ComObject WScript.Shell
foreach ($dir in $places) {
	$lnk = Join-Path $dir "Play NetHack Voxel.lnk"
	$s = $shell.CreateShortcut($lnk)
	$s.TargetPath = $exe
	$s.Arguments = "--go --world worlds\nethack --name $name --password `"`""
	$s.WorkingDirectory = $engine
	$s.IconLocation = "$exe,0"
	$s.Description = "Play NetHack Voxel"
	$s.Save()
	Write-Host "Made $lnk"
}
