# One-shot auto setup helper. Finds Steam L4D2, the Minecraft launcher folder and
# a JDK, then runs Setup-L4D2MC.ps1 with the toolchains bundled in this checkout.
# Everything is logged to setup-log.txt and the window stays open on errors.
param([switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$log = Join-Path $PSScriptRoot 'setup-log.txt'
try { Start-Transcript -Path $log -Force | Out-Null } catch { }
$exitCode = 0
function Test-SubExists {
    param([string]$Path, [string]$Sub)
    if (!$Path) { return $false }
    try { return (Test-Path -LiteralPath ($Path.TrimEnd('\') + '\' + $Sub)) } catch { return $false }
}
function Get-DriveGamePaths {
    param([string]$Drive)
    $drive = $Drive.TrimEnd('\')
    if ($drive -notmatch ':$') { $drive = $drive + ':' }
    $paths = @()
    foreach ($sub in @('SteamLibrary\steamapps\common\Left 4 Dead 2',
                       'Steam\steamapps\common\Left 4 Dead 2',
                       'Program Files (x86)\Steam\steamapps\common\Left 4 Dead 2',
                       'Games\SteamLibrary\steamapps\common\Left 4 Dead 2',
                       'Games\Steam\steamapps\common\Left 4 Dead 2')) {
        $paths += ($drive + '\' + $sub)
    }
    foreach ($vdf in @(($drive + '\SteamLibrary\steamapps\libraryfolders.vdf'),
                       ($drive + '\Steam\steamapps\libraryfolders.vdf'),
                       ($drive + '\Program Files (x86)\Steam\steamapps\libraryfolders.vdf'))) {
        if (Test-Path -LiteralPath $vdf) {
            foreach ($line in Get-Content -LiteralPath $vdf) {
                if ($line -match '"path"\s+"([^"]+)"') {
                    $paths += (($Matches[1] -replace '\\\\', '\') + '\steamapps\common\Left 4 Dead 2')
                }
            }
        }
    }
    return $paths
}
function Find-Game {
    $candidates = @()
    try {
        $cfg = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'l4d2mc.local.json') -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
        if ($cfg.game) { $candidates += [string]$cfg.game }
    } catch { }
    try {
        $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath
        $candidates += (Join-Path $steam 'steamapps\common\Left 4 Dead 2')
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            foreach ($line in Get-Content -LiteralPath $vdf) {
                if ($line -match '"path"\s+"([^"]+)"') {
                    $candidates += (($Matches[1] -replace '\\\\', '\') + '\steamapps\common\Left 4 Dead 2')
                }
            }
        }
    } catch { }
    $candidates += @('C:\Program Files (x86)\Steam\steamapps\common\Left 4 Dead 2',
                     'C:\Program Files\Steam\steamapps\common\Left 4 Dead 2',
                     'D:\SteamLibrary\steamapps\common\Left 4 Dead 2',
                     'E:\SteamLibrary\steamapps\common\Left 4 Dead 2')
    foreach ($drive in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        $candidates += (Get-DriveGamePaths $drive.Root)
    }
    foreach ($c in $candidates) {
        if ($c -and (Test-SubExists $c 'left4dead2.exe')) { return $c }
    }
    return ''
}
function Find-Minecraft {
    $candidates = @("$env:APPDATA\.minecraft",
                    "$env:APPDATA\.tlauncher\legacy\Minecraft\game",
                    "$env:APPDATA\.tlauncher")
    foreach ($c in $candidates) {
        if ($c -and (Test-SubExists $c 'versions')) { return $c }
    }
    return ''
}
function Find-Java {
    $candidates = @($env:JAVA_HOME)
    $roots = @((Join-Path $env:ProgramFiles 'Eclipse Adoptium'),
               (Join-Path $env:ProgramFiles 'Java'),
               (Join-Path ${env:ProgramFiles(x86)} 'Eclipse Adoptium'))
    foreach ($root in $roots) {
        if ($root -and (Test-Path -LiteralPath $root)) {
            $candidates += (Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue).FullName
        }
    }
    $fallback = ''
    foreach ($c in $candidates) {
        if (!$c) { continue }
        $exe = Join-Path $c 'bin\java.exe'
        if (!(Test-Path -LiteralPath $exe)) { continue }
        # java -version writes to stderr; with ErrorActionPreference=Stop the
        # 2>&1 redirect makes PS 5.1 turn it into a terminating error, so
        # relax it for the duration of the call.
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $version = (& $exe -version 2>&1 | ForEach-Object { "$_" } | Out-String).Split("`n")[0].Trim()
        } catch {
            $version = ''
        } finally {
            $ErrorActionPreference = $prevEap
        }
        Write-Host ("Java candidate: " + $c + " -> " + $version)
        if ($version -match '"25\.') { return $c }
        if (!$fallback) { $fallback = $c }
    }
    return $fallback
}
try {
    Write-Host '=== L4D2MC auto setup ==='
    Write-Host ('Working folder: ' + $PSScriptRoot)
    if (!(Get-Command python -ErrorAction SilentlyContinue)) {
        throw "Python was not found in PATH. Install Python 3.12+ from python.org and enable 'Add python.exe to PATH' during installation, then run this script again."
    }
    Write-Host ('Python: ' + (python --version 2>&1))
    $game = Find-Game
    if (!$game) {
        Write-Host 'L4D2 was not found automatically. Enter the L4D2 install root (the folder containing left4dead2.exe).'
        $game = (Read-Host 'L4D2 folder').Trim('"', ' ')
    if ($game -match '^[a-zA-Z]:?$') {
        $drive = if ($game.Length -eq 1) { $game + ':' } else { $game }
        Write-Host ('Searching drive ' + $drive + ' for the Steam L4D2 library...')
        foreach ($cand in (Get-DriveGamePaths $drive)) {
            if (Test-SubExists $cand 'left4dead2.exe') { $game = $cand; break }
        }
    }
    }
    if (!(Test-SubExists $game 'left4dead2.exe')) {
        throw ('L4D2 not found at: ' + $game)
    }
    Write-Host ('L4D2: ' + $game)
    $mc = Find-Minecraft
    if (!$mc) {
        Write-Host 'Minecraft launcher folder was not found automatically. Enter the folder that contains versions\.'
        $mc = (Read-Host 'Minecraft folder').Trim('"', ' ')
    }
    if (!(Test-SubExists $mc 'versions')) {
        throw ('Minecraft launcher folder with versions\ not found at: ' + $mc)
    }
    Write-Host ('Minecraft: ' + $mc)
    $reshade = Join-Path $PSScriptRoot 'toolchains\ReShade32.dll'
    $zig = Join-Path $PSScriptRoot 'toolchains\zig-x86_64-windows-0.15.2\zig.exe'
    $include = Join-Path $PSScriptRoot 'toolchains\reshade-6.8.0\include'
    $squirrel = Join-Path $PSScriptRoot 'toolchains\squirrel-parser\sq.exe'
    $portableSquirrel=Join-Path $PSScriptRoot 'toolchains\squirrel-parser\sq-win32.exe'
    if(Test-Path -LiteralPath $portableSquirrel){$squirrel=$portableSquirrel}
    foreach ($tool in @($reshade, $zig, $include, $squirrel)) {
        if (!(Test-Path -LiteralPath $tool)) { throw ('Missing bundled toolchain component: ' + $tool) }
    }
    Write-Host 'ReShade32.dll, zig.exe, ReShade SDK headers and sq.exe: found.'
    $zigLibrary=Join-Path (Split-Path $zig -Parent) 'lib\std\Build'
    foreach($part in @('Cache.zig','Fuzz.zig','Module.zig','Step.zig','Watch.zig','WebServer.zig','abi.zig')) {
        if(!(Test-Path -LiteralPath (Join-Path $zigLibrary $part))) {
            throw ('Incomplete bundled Zig standard library: lib\std\Build\'+$part+
                '. Extract l4d2mc-setup-fix.zip over this project folder or use the corrected friend archive, then rerun setup.')
        }
    }
    $java = Find-Java
    if ($java) { Write-Host ('Using Java: ' + $java) }
    else {
        Write-Warning 'No JDK found. The guest mod build needs JDK 25. Setup will continue, but it may fail at the guest build step.'
        $java = (Read-Host 'Optional path to a JDK 25 folder (press Enter to skip)').Trim('"', ' ')
    }
    if ($CheckOnly) {
        Write-Host '=== Preflight OK. Nothing was installed (check mode). ==='
        Write-Host ('Setup would run with: -Game ' + $game + ' -Minecraft ' + $mc + ' -JavaHome ' + $java)
        return
    }
    Write-Host '=== Installing python requirements ==='
    python -m pip install -r (Join-Path $PSScriptRoot 'requirements.txt')
    Write-Host '=== Running Setup-L4D2MC.ps1 (this can take a while, do not close the window) ==='
    & (Join-Path $PSScriptRoot 'Setup-L4D2MC.ps1') `
        -Game $game -Minecraft $mc -ReShadeDll $reshade -JavaHome $java `
        -Zig $zig -ReShadeInclude $include -Squirrel $squirrel
    Write-Host '=== SETUP OK ==='
    Write-Host 'Now start the L4D2MC-Fabric-26.3 profile in the Minecraft launcher, keep Minecraft running, then start Launch-L4D2MC-2K.bat.'
}
catch {
    $exitCode = 1
    Write-Host ''
    Write-Host '=== SETUP FAILED ==='
    Write-Host ($_ | Out-String)
    Write-Host 'Full log: setup-log.txt next to this script. Send the whole file to the person helping you.'
}
finally {
    try { Stop-Transcript | Out-Null } catch { }
}
Read-Host 'Done. Press Enter to close this window'
exit $exitCode


