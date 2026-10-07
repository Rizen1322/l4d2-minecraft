param(
    [string]$Game = 'E:\SteamLibrary\steamapps\common\Left 4 Dead 2',
    [string]$Map = 'c1m1_hotel',
    [switch]$KeepOtherAddons
)
$ErrorActionPreference = 'Stop'
if ($Map -notmatch '^[a-zA-Z0-9_]+$') { throw 'Invalid map name' }
if (Get-Process -Name left4dead2 -ErrorAction SilentlyContinue) {
    throw 'Close L4D2 before starting Block Sandbox.'
}
$gamePath = (Resolve-Path -LiteralPath $Game).Path
$gameExe = Join-Path $gamePath 'left4dead2.exe'
$addonPath = Join-Path $gamePath 'left4dead2\addons\l4d2mc_blocks.vpk'
if (-not (Test-Path -LiteralPath $addonPath)) { throw 'Install the addon first: python tools/manage.py install' }
$listPath = Join-Path $gamePath 'left4dead2\addonlist.txt'
$sessionDir = Join-Path $PSScriptRoot ('backups\play-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null
$listExisted = Test-Path -LiteralPath $listPath
$backupPath = Join-Path $sessionDir 'addonlist.txt'
if ($listExisted) { Copy-Item -LiteralPath $listPath -Destination $backupPath }
$restoring = -not $KeepOtherAddons
try {
    if ($restoring) {
        $text = if ($listExisted) { Get-Content -LiteralPath $listPath -Raw } else { '"AddonList" { }' }
        $text = [regex]::Replace($text, '"1"', '"0"')
        $text = [regex]::Replace($text, '(?m)^\s*"l4d2mc_blocks\.vpk"\s*"[01]"\s*$', '')
        $closing = $text.LastIndexOf('}')
        if ($closing -lt 0) { throw 'Invalid addonlist; original remains in the session backup' }
        $text = $text.Substring(0, $closing) + '"l4d2mc_blocks.vpk" "1"' + "`r`n}"
        [System.IO.File]::WriteAllText($listPath, $text, [System.Text.UTF8Encoding]::new($false))
    }
    Write-Host 'Starting local Block Sandbox. Other addons are restored when you close the game.'
    Start-Process -FilePath 'C:\Program Files (x86)\Steam\steam.exe' -ArgumentList @(
        '-applaunch', '550', '-insecure', '-novid', '-console', '+map', $Map, 'mcblocks'
    ) -WindowStyle Hidden
    $deadline = (Get-Date).AddSeconds(60)
    $gameProcess = $null
    do {
        Start-Sleep -Milliseconds 500
        $gameProcess = Get-Process -Name left4dead2 -ErrorAction SilentlyContinue | Select-Object -First 1
        if ((Get-Date) -gt $deadline) { throw 'L4D2 did not start within 60 seconds' }
    } until ($gameProcess)
    $gameProcess.WaitForExit()
} finally {
    if ($restoring -and $listExisted) { Copy-Item -LiteralPath $backupPath -Destination $listPath }
    # If there was no list before, leave the generated list enabling this single addon.
    Write-Host ('Session backup: ' + $sessionDir)
}
