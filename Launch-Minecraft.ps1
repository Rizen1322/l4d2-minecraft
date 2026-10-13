param([string]$Game = '', [ValidatePattern('^[a-zA-Z0-9_]+$')][string]$Map = 'c1m1_hotel', [ValidateRange(320,3840)][int]$Width = 1280, [ValidateRange(240,2160)][int]$Height = 720, [switch]$Borderless, [ValidateSet("quality","balanced","low")][string]$Performance = "quality")
$ErrorActionPreference = 'Stop'
# Optional local room settings; credentials stay in this file, never command arguments.
$coopPath = Join-Path $PSScriptRoot 'l4d2mc.coop.json'
$coopJoin = $false
$coopServer = ''
if (Test-Path -LiteralPath $coopPath) {
    $coopSettings = Get-Content -LiteralPath $coopPath -Raw | ConvertFrom-Json
    if ($coopSettings.mode -notin @('host','join')) { throw 'Co-op mode must be host or join.' }
    $coopJoin = $coopSettings.mode -eq 'join'
    if ($coopJoin) {
        $coopServer = [string]$coopSettings.l4d2server
        # Source console arguments must contain an address only, never command text.
        if ($coopServer -notmatch '^(?:[a-zA-Z0-9][a-zA-Z0-9.-]*|\[[a-fA-F0-9:]+\])(?::[0-9]{1,5})?$') {
            throw 'Co-op l4d2server must be a hostname/IP with an optional port.'
        }
    }
}

if (!$Game) {
    $Game = & python (Join-Path $PSScriptRoot 'passthrough\runtime_paths.py') game
    if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve game path. Set L4D2MC_GAME or pass -Game.' }
}
if (!(Test-Path -LiteralPath (Join-Path $Game 'left4dead2.exe'))) { throw 'L4D2 installation missing. Pass -Game or configure l4d2mc.local.json.' }
$steamRecord=Get-ItemProperty -LiteralPath 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue
$steamExe=$steamRecord.SteamExe
if (!$steamExe) { $steamExe=Join-Path ${env:ProgramFiles(x86)} 'Steam/steam.exe' }
if (!(Test-Path -LiteralPath $steamExe)) { throw 'Steam executable missing. Start Steam once so its per-user path is registered.' }
$existingBridge=Get-CimInstance Win32_Process -Filter "Name='python.exe'" | Where-Object {
    $_.CommandLine -match 'l4d2-minecraft[\\/]passthrough[\\/]bridge.py'
}
if ($existingBridge) { throw 'A Minecraft bridge is already running. Close its launcher before starting another.' }
$launcherCreated=$false
$launcherMutex=[Threading.Mutex]::new($true,'Local\L4D2MinecraftLauncher',[ref]$launcherCreated)
if (!$launcherCreated) { $launcherMutex.Dispose();throw 'L4D2MC launcher is already running.' }
$taskRoot = $PSScriptRoot
$gameExe = Join-Path $Game 'left4dead2.exe'
$addonList = Join-Path $Game 'left4dead2\addonlist.txt'
$poseFile = Join-Path $Game 'left4dead2\ems\l4d2mc_pose.txt'
$cfgName = 'l4d2mc_bridge_init_' + [Guid]::NewGuid().ToString('N')
$cfg = Join-Path $Game ('left4dead2\cfg\' + $cfgName + '.cfg')
$playCfgName = $cfgName + '_play'
$restoreCfgName = $cfgName + '_restore'
$playCfg = Join-Path $Game ('left4dead2\cfg\' + $playCfgName + '.cfg')
$restoreCfg = Join-Path $Game ('left4dead2\cfg\' + $restoreCfgName + '.cfg')
$configFile = Join-Path $Game 'left4dead2\cfg\config.cfg'
$controlRecovery = Join-Path $taskRoot 'backups\passthrough-launch-controls.json'
$controlledKeys = @('MOUSE1','MOUSE2','MOUSE3','MWHEELUP','MWHEELDOWN','e','q','f','t','/','F5','F9') + (1..9 | ForEach-Object {[string]$_})
$controlledVars = @('r_drawviewmodel','crosshair','cam_idealdist','cam_idealyaw','cam_idealpitch','cam_ideallag','c_thirdpersonshoulderoffset','c_maxyaw','c_minyaw','m_pitch')
if (!('L4D2MC.MonotonicClock' -as [type])) {
    Add-Type -Namespace L4D2MC -Name MonotonicClock -MemberDefinition '[System.Runtime.InteropServices.DllImport("kernel32.dll")] public static extern ulong GetTickCount64();'
}
function Test-SourceRenderReady {
    $statusMap=$null;$statusView=$null
    try {
        $statusMap=[IO.MemoryMappedFiles.MemoryMappedFile]::OpenExisting('Local\L4D2MinecraftRenderPose',[IO.MemoryMappedFiles.MemoryMappedFileRights]::Read)
        $statusView=$statusMap.CreateViewAccessor(0,128,[IO.MemoryMappedFiles.MemoryMappedFileAccess]::Read)
        $statusStamp=$statusView.ReadInt64(72)
        if($statusStamp -eq 0){return $true}
        $statusAge=[long][L4D2MC.MonotonicClock]::GetTickCount64()-$statusStamp
        return $statusAge -ge 0 -and $statusAge -lt 2000 -and $statusView.ReadInt32(64) -ne 0
    } catch { return $true }
    finally {if($statusView){$statusView.Dispose()};if($statusMap){$statusMap.Dispose()}}
}
function Restore-ControlFile($snapshot) {
    if (!(Test-Path -LiteralPath $configFile)) { return }
    $lines = [IO.File]::ReadAllLines($configFile)
    $kept = foreach ($line in $lines) {
        if ($line -match '^bind\s+"([^"]+)"' -and $controlledKeys -contains $Matches[1]) { continue }
        if ($line -match '^([^\s]+)\s+' -and $controlledVars -contains $Matches[1]) { continue }
        $line
    }
    [IO.File]::WriteAllLines($configFile,@($kept)+@($snapshot.lines),[Text.Encoding]::UTF8)
}
if (Get-Process left4dead2 -ErrorAction SilentlyContinue) {
    throw 'Close the current L4D2 session before starting the prototype.'
}
& python (Join-Path $taskRoot 'passthrough\update.py') --game $Game
if ($LASTEXITCODE -ne 0) { throw 'Built mashup update could not be applied.' }
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
    if (Test-Path -LiteralPath $controlRecovery) { Restore-ControlFile (Get-Content -LiteralPath $controlRecovery -Raw | ConvertFrom-Json) }
    Remove-Item -LiteralPath $marker
}
$initialAddons = [IO.File]::ReadAllBytes($addonList)
$savedLines = foreach ($line in [IO.File]::ReadAllLines($configFile)) {
    if (($line -match '^bind\s+"([^"]+)"' -and $controlledKeys -contains $Matches[1]) -or
        ($line -match '^([^\s]+)\s+' -and $controlledVars -contains $Matches[1])) {
        # The front F5 view inverts m_pitch; a crash there must not persist inverted mouse.
        if ($line -match '^m_pitch\s+"?-') { $line -replace '^(m_pitch\s+"?)-','$1' } else { $line }
    }
}
$controlSnapshot = @{lines=@($savedLines)}
$controlSnapshot | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $controlRecovery -Encoding UTF8
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
    if ($addonText -match '"l4d2mc_hud\.vpk"') {
        $addonText = [regex]::Replace($addonText,'("l4d2mc_hud\.vpk"\s*)"[01]"','$1"1"')
    } else {
        $addonText = [regex]::Replace($addonText,'}\s*$','"l4d2mc_hud.vpk" "1"' + "`n}")
    }
    [IO.File]::WriteAllText($addonList, $addonText)
    if (!$coopJoin) {
        # A co-op host must accept the teammate's direct +connect, not only lobby joins.
        $hostCommands = if (Test-Path -LiteralPath $coopPath) { "sv_allow_lobby_connect_only 0`n" } else { '' }
        [IO.File]::WriteAllText($cfg, $hostCommands + "sv_cheats 1`nscript_execute l4d2mc_bridge`n", [Text.Encoding]::ASCII)
    }
    $release = "-attack`n-attack2`n-use`n-zoom`n"
    $playText = $release + (($controlledKeys | ForEach-Object {'unbind "' + $_ + '"'}) -join "`n") + "`n"
    if (!$coopJoin) {
        $playText += 'bind "MWHEELUP" "script L4D2MCBridge.gameplay.wheel++"' + "`n"
        $playText += 'bind "MWHEELDOWN" "script L4D2MCBridge.gameplay.wheel--"' + "`n"
    }
    $playText += "cl_mouseenable 1`nr_drawviewmodel 0`ncrosshair 0`nfirstperson`n"
    [IO.File]::WriteAllText($playCfg,$playText,[Text.Encoding]::ASCII)
    $restoreText = $release + (($controlledKeys | ForEach-Object {'unbind "' + $_ + '"'}) -join "`n") + "`nr_drawviewmodel 1`ncrosshair 1`ncam_ideallag 4`nfirstperson`n" + ($savedLines -join "`n") + "`ncl_mouseenable 1`n"
    [IO.File]::WriteAllText($restoreCfg,$restoreText,[Text.Encoding]::ASCII)
    $bridgeScript = Join-Path $taskRoot 'passthrough\bridge.py'
    $windowFlags = '-windowed -w ' + $Width + ' -h ' + $Height
    if($Borderless){$windowFlags += ' -noborder'}
    $bridgeArguments = @('-u', ('"' + $bridgeScript + '"'), '--game', ('"' + $Game + '"'), '--play-cfg', $playCfgName, '--restore-cfg', $restoreCfgName, '--width', ([string]$Width), '--height', ([string]$Height), '--performance', $Performance)
    if (Test-Path -LiteralPath $coopPath) { $bridgeArguments += @('--coop-config', ('"' + $coopPath + '"')) }
    $bridgeProcess = Start-Process -FilePath $pythonExe -ArgumentList $bridgeArguments -WorkingDirectory $taskRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $evidence 'bridge-runtime.log') -RedirectStandardError (Join-Path $evidence 'bridge-errors.log')
    # Solo: a LAN-only local server never validates Steam tickets, so a flaky Steam
    # connection cannot drop the host ("STEAMAUTH failure code 8 / No Steam logon").
    # Co-op keeps normal auth: VPN ranges such as Radmin's 26.x are not LAN addresses.
    $sourceDestination = if ($coopJoin) { '+connect ' + $coopServer } elseif (Test-Path -LiteralPath $coopPath) { '+map ' + $Map } else { '+sv_lan 1 +map ' + $Map }
    Start-Process -FilePath $steamExe -ArgumentList ('-applaunch 550 -insecure -novid ' + $windowFlags + ' -console -condebug ' + $sourceDestination) -WindowStyle Hidden
    $deadline = [DateTime]::UtcNow.AddSeconds(120)
    $nextProbe = [DateTime]::UtcNow.AddSeconds(12)
    $nextStatus = [DateTime]::UtcNow
    $roomStatusPath = Join-Path $Game 'left4dead2/ems/l4d2mc_room_status.txt'
    if ($coopJoin) {
        Write-Host 'Mode: joining a co-op host. Join the host L4D2 session with the player name entered in Coop.bat.'
        if ($coopSettings.player) { Write-Host ('Configured L4D2 player: ' + (ConvertTo-Json -InputObject ([string]$coopSettings.player) -Compress)) }
        else { Write-Host ('Configured L4D2 userid: ' + $coopSettings.userid) }
    }
    elseif (Test-Path -LiteralPath $coopPath) { Write-Host 'Mode: co-op host. Waiting for a teammate to join L4D2.' }
    else { Write-Host 'Mode: solo. For multiplayer, first configure host/join through Coop.bat on both PCs.' }
    Write-Host 'Waiting for L4D2 camera and Minecraft bridge (up to 120 seconds)...'
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($bridgeProcess.HasExited) {
            Get-Content -LiteralPath (Join-Path $evidence 'bridge-errors.log') -Tail 12 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_ }
            throw 'Minecraft bridge exited during startup. See evidence/bridge-errors.log.'
        }
        if ([DateTime]::UtcNow -ge $nextStatus) {
            if ($coopJoin -and (Test-Path -LiteralPath $roomStatusPath)) {
                try { $roomStatus = Get-Content -LiteralPath $roomStatusPath -Raw | ConvertFrom-Json; Write-Host ('Co-op: ' + $roomStatus.detail) } catch { Write-Host 'Waiting for room status...' }
            }
            Get-Content -LiteralPath (Join-Path $evidence 'bridge-runtime.log') -Tail 1 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_ }
            $nextStatus = [DateTime]::UtcNow.AddSeconds(5)
        }
        $hostProcess = Get-Process left4dead2 -ErrorAction SilentlyContinue | Where-Object {$_.MainWindowHandle -ne 0} | Select-Object -First 1
        if (!$coopJoin -and $hostProcess -and [DateTime]::UtcNow -ge $nextProbe -and (Test-SourceRenderReady)) {
            & $pythonExe (Join-Path $taskRoot 'passthrough/source_commands.py') --exec $cfgName
            $nextProbe = [DateTime]::UtcNow.AddSeconds(5)
        }
        if ((Test-Path -LiteralPath $poseFile) -and (Get-Item -LiteralPath $poseFile).LastWriteTimeUtc -gt [DateTime]::UtcNow.AddSeconds(-1)) { break }
        Start-Sleep -Milliseconds 500
    }
    if (!$hostProcess -or !(Test-Path -LiteralPath $poseFile) -or (Get-Item -LiteralPath $poseFile).LastWriteTimeUtc -lt [DateTime]::UtcNow.AddSeconds(-2)) {
        throw 'No L4D2 camera received. Send evidence/bridge-runtime.log and evidence/bridge-errors.log from BOTH PCs; also check the host L4D2 console.log.'
    }
    Write-Host 'Minecraft controls: LMB attack, RMB use, E inventory, 1-9/wheel hotbar, Q drop, F offhand, F5 camera, WASD/Space/Shift/Ctrl use original L4D2 binds.'
    Write-Host 'Keep Minecraft running and not minimized. Close L4D2 to restore Workshop flags.'
    while (!$hostProcess.HasExited) {
        if ($bridgeProcess.HasExited) { throw 'Minecraft bridge stopped. Mouse control is being restored.' }
        # Campaign transitions recreate the VScript VM and its think anchor.
        # Reattach only to this launcher-owned insecure host after a stale pose.
        if (!$coopJoin -and [DateTime]::UtcNow -ge $nextProbe -and
            (!(Test-Path -LiteralPath $poseFile) -or (Get-Item -LiteralPath $poseFile).LastWriteTimeUtc -lt [DateTime]::UtcNow.AddSeconds(-2)) -and (Test-SourceRenderReady)) {
            & $pythonExe (Join-Path $taskRoot 'passthrough/source_commands.py') --exec $cfgName
            $nextProbe = [DateTime]::UtcNow.AddSeconds(5)
        }
        Start-Sleep -Milliseconds 500
    }
} finally {
    if ($hostProcess -and !$hostProcess.HasExited) {
        & $pythonExe (Join-Path $taskRoot 'passthrough/source_commands.py') --exec $restoreCfgName
    }
    [IO.File]::WriteAllBytes($addonList, $initialAddons)
    if (Test-Path -LiteralPath $marker) { Remove-Item -LiteralPath $marker }
    if ($bridgeProcess -and !$bridgeProcess.HasExited) { Stop-Process -Id $bridgeProcess.Id }
    $launcherMutex.Dispose()
    Restore-ControlFile $controlSnapshot
    if (Test-Path -LiteralPath $cfg) { Remove-Item -LiteralPath $cfg }
    if (!$hostProcess -or $hostProcess.HasExited) {
        foreach ($ownedCfg in @($playCfg,$restoreCfg)) { if (Test-Path -LiteralPath $ownedCfg) { Remove-Item -LiteralPath $ownedCfg } }
    }
}
