<#
.SYNOPSIS
    Copies the UE4SS mod (src\<folder>) into the game's ue4ss\Mods\<folder>.

.DESCRIPTION
    Reads mod.json. The target is <game folder>\<win64Path>\ue4ss\Mods\<folder>; the game folder is
    $env:UE5_GAMES_DIR\<gameFolder> unless -GameDir or -ModsDir is given. UE4SS must be installed in the game.

    The mod writes its own files into its folder while the game runs: tuning.lua, tuning_custom.lua,
    slash_choice.txt and slash_tuning.lua (the panel's settings) and logs\. So the script mirrors only Scripts\ and
    ui\ (the code and the panel art: files that are no longer in src are removed there) and copies the other shipped
    files (README.md, LICENSE, enabled.txt, logs\README.txt) without removing anything. Nothing else in ue4ss\Mods is touched. The mod folder holds enabled.txt, so UE4SS starts the
    mod without an entry in mods.txt. UE4SS loads Lua mods when the game starts, so a change shows after the next game
    start (or after the mod's own Ctrl+F8 reload, for every script but Scripts\main.lua).

    An existing config.lua in the game (the mod folder's root) stays: it holds the settings of the one who tests, and
    the mod takes the default for every setting it lacks. -ResetConfig copies the shipped one over it.

    Exit codes: 0 = deployed or already up to date, 1 = error.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\deploy.ps1
#>
param(
    # The game's install folder. Default: gameDir of _tools\gamedata\<game>\game.json, else $env:UE5_GAMES_DIR\<gameFolder of mod.json>.
    [string]$GameDir,
    # The UE4SS Mods folder. Default: <GameDir>\<win64Path of mod.json>\ue4ss\Mods.
    [string]$ModsDir,
    # Copy the shipped config.lua over the one in the game.
    [switch]$ResetConfig
)

$ErrorActionPreference = "Stop"

# The game folder: "gameDir" of _tools\gamedata\<game>\game.json, for a game outside UE5_GAMES_DIR (for example in a
# Steam library), else $env:UE5_GAMES_DIR\<gameFolder of mod.json>; $null when neither is known. The tools folder is
# $env:UE5_TOOLS, else the first _tools folder above the project (a plain clone has none).
function Get-GameDir {
    $toolsDir = $env:UE5_TOOLS
    if (-not $toolsDir -and $PSScriptRoot) {
        $dir = Split-Path $PSScriptRoot -Parent
        while (-not $toolsDir -and $dir) {
            if (Test-Path (Join-Path $dir "_tools")) {
                $toolsDir = Join-Path $dir "_tools"
            }
            $dir = Split-Path $dir -Parent
        }
    }
    if ($toolsDir) {
        $gameJson = Join-Path $toolsDir "gamedata\$($mod.game)\game.json"
        if (Test-Path $gameJson) {
            $gameInfo = Get-Content $gameJson -Raw | ConvertFrom-Json
            if ($gameInfo.gameDir) {
                return $gameInfo.gameDir
            }
        }
    }
    if ($env:UE5_GAMES_DIR) {
        return Join-Path $env:UE5_GAMES_DIR $mod.gameFolder
    }
    return $null
}

# robocopy with the quiet options; exit codes of 8 and more are errors.
function Invoke-Copy([string]$From, [string]$To, [string[]]$Extra) {
    robocopy $From $To @("/NFL", "/NDL", "/NJH", "/NJS", "/NP") @Extra | Out-Null
    $result = $LASTEXITCODE
    if ($result -ge 8) {
        throw "robocopy $From -> $To failed with exit code $result"
    }
    return $result
}

# -Encoding UTF8: Windows PowerShell 5.1 reads a file without a byte order mark as ANSI, and the name has an en dash.
$mod = Get-Content (Join-Path $PSScriptRoot "mod.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$source = Join-Path $PSScriptRoot "src\$($mod.folder)"
if (-not (Test-Path (Join-Path $source "Scripts\main.lua"))) {
    throw "$source\Scripts\main.lua not found."
}
if (-not $ModsDir) {
    if (-not $GameDir) {
        $GameDir = Get-GameDir
    }
    if (-not $GameDir) {
        throw "The game folder is unknown: set UE5_GAMES_DIR (the folder that holds '$($mod.gameFolder)'), give the game a gameDir in _tools\gamedata\$($mod.game)\game.json, or use -GameDir or -ModsDir."
    }
    $ue4ss = Join-Path (Join-Path $GameDir $mod.win64Path) "ue4ss"
    if (-not (Test-Path (Join-Path $ue4ss "UE4SS.dll"))) {
        throw "UE4SS is not installed in the game ($ue4ss\UE4SS.dll is missing). Install UE4SS first."
    }
    $ModsDir = Join-Path $ue4ss "Mods"
}
$target = Join-Path $ModsDir $mod.folder

# robocopy's exit code is a set of bits: 1 = files copied, 2 = extra files in the target (removed by /MIR).
$changed = $false
# The code and the panel art: mirrored.
foreach ($part in @("Scripts", "ui")) {
    $result = Invoke-Copy (Join-Path $source $part) (Join-Path $target $part) @("/MIR")
    if ($result -band 3) { $changed = $true }
}
# Everything else that ships: copied, nothing removed (the player's files there are "extra" to robocopy and stay).
# robocopy neither copies nor removes an excluded file, so /XF keeps the game's config.lua.
$keepConfig = (-not $ResetConfig) -and (Test-Path (Join-Path $target "config.lua"))
$rest = @("/E", "/XD", (Join-Path $source "Scripts"), (Join-Path $source "ui"))
if ($keepConfig) {
    $rest += @("/XF", "config.lua")
}
$result = Invoke-Copy $source $target $rest
if ($result -band 1) { $changed = $true }

if (-not $changed) {
    Write-Host "Already up to date: $target" -ForegroundColor Green
} else {
    Write-Host "Deployed $($mod.name) $($mod.version) to $target (active from the next game start)" -ForegroundColor Green
}
if ($keepConfig) {
    Write-Host "Kept the game's config.lua; -ResetConfig copies the shipped one."
}
exit 0
