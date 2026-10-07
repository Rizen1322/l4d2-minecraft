param([string]$Game = 'E:\SteamLibrary\steamapps\common\Left 4 Dead 2')
$ErrorActionPreference = 'Stop'
$taskRoot = $PSScriptRoot
$gameExe = Join-Path $Game 'left4dead2.exe'
$addonList = Join-Path $Game 'left4dead2\addonlist.txt'
$poseFile = Join-Path $Game 'left4dead2\ems\l4d2mc_pose.txt'
$cfgName = 'l4d2mc_bridge_init_' + [Guid]::NewGuid().ToString('N')
$cfg = Join-Path $Game ('left4dead2\cfg\' + $cfgName + '.cfg')
if (Get-Process left4dead2 -ErrorAction SilentlyContinue) {
    throw 'Close the current L4D2 session before starting the prototype.'
}
if (!(Test-Path -LiteralPath (Join-Path $Game 'bin\l4d2mc\L4D2Minecraft.addon32'))) {
    throw 'Install the passthrough adapter first.'
}
$recovery = Join-Path $taskRoot 'backups\passthrough-launch-addonlist.txt'
$marker = Join-Path $taskRoot 'backups\passthrough-launch-active.json'
if (Test-Path -LiteralPath $marker) {
    $previous = Get-Content -LiteralPath $marker -Raw | ConvertFrom-Json
    $previousOwner = Get-Process -Id $previous.pid -ErrorAction SilentlyContinue
    if ($previousOwner -and $previousOwner.StartTime.ToUniversalTime().Ticks -eq $previous.started) {
        throw 'Another prototype launcher is active.'
    }
    if (!(Test-Path -LiteralPath $recovery)) { throw 'Recovery addon-list backup is missing.' }
    [IO.File]::WriteAllBytes($addonList, [IO.File]::ReadAllBytes($recovery))
    Remove-Item -LiteralPath $marker
}
$initialAddons = [IO.File]::ReadAllBytes($addonList)
$bridgeProcess = $null
$hostProcess = $null
$pythonExe = (Get-Command python).Source
$evidence = Join-Path $taskRoot 'evidence'
[IO.Directory]::CreateDirectory($evidence) | Out-Null
[IO.File]::WriteAllBytes($recovery, $initialAddons)
$launchOwner = Get-Process -Id $PID
@{pid=$PID;started=$launchOwner.StartTime.ToUniversalTime().Ticks} | ConvertTo-Json | Set-Content -LiteralPath $marker
try {
    # Isolate this local prototype from inconsistent Workshop survivor/infected skins.
    $addonText = [IO.File]::ReadAllText($addonList)
    $addonText = [regex]::Replace($addonText, '("[^"\r\n]+\.vpk"\s*)"[01]"', '$1"0"')
    [IO.File]::WriteAllText($addonList, $addonText)
    [IO.File]::WriteAllText($cfg, "sv_cheats 1`nscript_execute l4d2mc_bridge`n", [Text.Encoding]::ASCII)
    $bridgeScript = Join-Path $taskRoot 'passthrough\bridge.py'
    $bridgeProcess = Start-Process -FilePath $pythonExe -ArgumentList @('"' + $bridgeScript + '"', '--game', '"' + $Game + '"') -WorkingDirectory $taskRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $evidence 'bridge-runtime.log') -RedirectStandardError (Join-Path $evidence 'bridge-errors.log')
    Start-Process 'C:\Program Files (x86)\Steam\steam.exe' -ArgumentList '-applaunch 550 -insecure -novid -windowed -w 1280 -h 720 -console -condebug +map c1m1_hotel' -WindowStyle Hidden
    $deadline = [DateTime]::UtcNow.AddSeconds(120)
    $nextProbe = [DateTime]::UtcNow.AddSeconds(12)
    while ([DateTime]::UtcNow -lt $deadline) {
        $hostProcess = Get-Process left4dead2 -ErrorAction SilentlyContinue | Where-Object {$_.MainWindowHandle -ne 0} | Select-Object -First 1
        if ($hostProcess -and [DateTime]::UtcNow -ge $nextProbe) {
            Start-Process -FilePath $gameExe -ArgumentList ('-hijack +exec ' + $cfgName) -WindowStyle Hidden
            $nextProbe = [DateTime]::UtcNow.AddSeconds(5)
        }
        if ((Test-Path -LiteralPath $poseFile) -and (Get-Item -LiteralPath $poseFile).LastWriteTimeUtc -gt [DateTime]::UtcNow.AddSeconds(-1)) { break }
        Start-Sleep -Milliseconds 500
    }
    if (!$hostProcess -or !(Test-Path -LiteralPath $poseFile) -or (Get-Item -LiteralPath $poseFile).LastWriteTimeUtc -lt [DateTime]::UtcNow.AddSeconds(-2)) {
        throw 'Local test map did not produce camera data. See L4D2 console.log.'
    }
    Write-Host 'L4D2MC prototype: V place, B break, N next slot, F9 inventory, Esc close inventory.'
    Write-Host 'Keep Minecraft running and not minimized. Close L4D2 to restore Workshop flags.'
    while (!$hostProcess.HasExited) {
        if ($bridgeProcess.HasExited) { throw 'Minecraft bridge stopped. Mouse control is being restored.' }
        Start-Sleep -Milliseconds 500
    }
} finally {
    if ($hostProcess -and !$hostProcess.HasExited) {
        Start-Process -FilePath $gameExe -ArgumentList '-hijack +cl_mouseenable 1' -WindowStyle Hidden
    }
    [IO.File]::WriteAllBytes($addonList, $initialAddons)
    if (Test-Path -LiteralPath $marker) { Remove-Item -LiteralPath $marker }
    if ($bridgeProcess -and !$bridgeProcess.HasExited) { Stop-Process -Id $bridgeProcess.Id }
    if (Test-Path -LiteralPath $cfg) { Remove-Item -LiteralPath $cfg }
}
