param([string]$Game='', [string]$JavaHome=$env:JAVA_HOME, [string]$Zig='', [string]$ReShadeInclude='', [string]$Squirrel='')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $projectRoot
New-Item -ItemType Directory -Force -Path (Join-Path $projectRoot 'dist') | Out-Null
# Native tools (zig, python, squirrel) write progress and errors to stderr.
# With ErrorActionPreference=Stop, PS 5.1 turns their stderr lines (captured via 2>&1)
# into terminating errors, so relax EAP around native calls through this helper.
function Invoke-NativeCapture {
    param([scriptblock]$Command, [string]$LogPath)
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $Command 2>&1 | ForEach-Object { "$_" }
    } finally {
        $ErrorActionPreference = $prevEap
    }
    $exitCode = $LASTEXITCODE
    $text = ($output -join "`r`n")
    if ($LogPath -and $text.Trim()) { Set-Content -LiteralPath $LogPath -Value $text -Encoding UTF8 }
    foreach ($line in $output) { Write-Host $line }
    return @{ ExitCode = $exitCode; Text = $text }
}
if (!$Game) { $Game = & python passthrough/runtime_paths.py game; if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve L4D2 path.' } }
if (!$JavaHome) {
    $javaCommand=Get-Command java -ErrorAction SilentlyContinue
    if ($javaCommand) { $JavaHome=Split-Path (Split-Path $javaCommand.Source -Parent) -Parent }
    else { $JavaHome=Join-Path $env:APPDATA '.tlauncher\legacy\Minecraft\jre\java-runtime-epsilon\windows-x64\java-runtime-epsilon' }
}
if (!(Test-Path -LiteralPath (Join-Path $JavaHome 'bin/java.exe'))) { throw 'Java25 required: set JAVA_HOME or pass -JavaHome.' }
$env:JAVA_HOME=$JavaHome
if (!$Zig) {
    $zigCommand=Get-Command zig -ErrorAction SilentlyContinue
    $Zig=if ($zigCommand) {$zigCommand.Source} else {Join-Path $projectRoot 'toolchains/zig-x86_64-windows-0.15.2/zig.exe'}
}
if (!(Test-Path -LiteralPath $Zig)) { throw 'Zig0.15.2 required: put zig on PATH or pass -Zig.' }
if (!$ReShadeInclude) { $ReShadeInclude=Join-Path $projectRoot 'toolchains/reshade-6.8.0/include' }
if (!(Test-Path -LiteralPath (Join-Path $ReShadeInclude 'reshade.hpp'))) { throw 'ReShade6.8 SDK headers required: pass -ReShadeInclude.' }
if (!$Squirrel) {
    $Squirrel=Join-Path $projectRoot 'toolchains/squirrel-parser/sq-win32.exe'
    if(!(Test-Path -LiteralPath $Squirrel)){$Squirrel=Join-Path $projectRoot 'toolchains/squirrel-parser/sq.exe'}
}
if (!(Test-Path -LiteralPath $Squirrel)) { throw 'Standalone Squirrel3.2 compiler required: pass -Squirrel. Full Source checks cannot be skipped.' }
. (Join-Path $PSScriptRoot 'source_checks.ps1')
$sourceLog=Join-Path $projectRoot 'dist/source-check.log'
$probe=Invoke-SourceProcess -Executable $Squirrel -CheckArguments @('-v') -LogPath $sourceLog
if($probe.ExitCode -ne 0 -or !$probe.Text.Contains('Squirrel')) {
    $fallback=Join-Path (Split-Path $Squirrel -Parent) 'sq-win32.exe'
    if(Test-Path -LiteralPath $fallback) {
        $alternate=Invoke-SourceProcess -Executable $fallback -CheckArguments @('-v') -LogPath $sourceLog
        if($alternate.ExitCode -eq 0 -and $alternate.Text.Contains('Squirrel')){$Squirrel=$fallback;$probe=$alternate}
    }
    if($probe.ExitCode -ne 0 -or !$probe.Text.Contains('Squirrel')) {
        throw ('Squirrel executable could not start: exit '+$probe.ExitCode+' ('+$probe.HexCode+'). '+$probe.Text+' See dist/source-check.log.')
    }
}
Write-Host ('Squirrel preflight: '+$Squirrel+'; '+$probe.Text.Trim())
$cubeComplete=$true
foreach ($extension in @('mdl','phy','vvd','dx90.vtx')) { if (!(Test-Path -LiteralPath (Join-Path $projectRoot ('addon/models/l4d2mc/cube.'+$extension)))) { $cubeComplete=$false } }
foreach ($material in @('dirt','stone','wood')) { foreach ($extension in @('vmt','vtf')) { if (!(Test-Path -LiteralPath (Join-Path $projectRoot ('addon/materials/l4d2mc/'+$material+'.'+$extension)))) { $cubeComplete=$false } } }
if (!$cubeComplete) {
    python tools/build_assets.py --game $Game
    if ($LASTEXITCODE -ne 0) { throw 'Own collision model build failed.' }
}
python tools/private_hud_assets.py --game $Game
if ($LASTEXITCODE -ne 0) { throw 'Private teammate asset conversion failed' }
python tools/build_hud.py --game $Game
if ($LASTEXITCODE -ne 0) { throw 'Private native HUD package failed' }
& '.\passthrough\guest\gradlew.bat' -p '.\passthrough\guest' build --no-daemon
if ($LASTEXITCODE -ne 0) { throw 'Guest build failed' }
# ReShade is built with MSVC. Its x86 member functions return small handle
# structs through a hidden pointer. compositor.cpp contains the explicit ABI wrapper.
$zigArgs = @('c++','-target','x86-windows-gnu','-std=c++17','-O2','-shared','-I',$ReShadeInclude,'passthrough/native/addon.cpp','passthrough/native/compositor.cpp','-o','dist/L4D2Minecraft.dll','-luser32')
$native = Invoke-NativeCapture -Command { & $Zig @zigArgs } -LogPath (Join-Path $projectRoot 'dist\native-build.log')
if ($native.ExitCode -ne 0) {
    throw ('Native build failed (zig exit ' + $native.ExitCode + '). Compiler output saved to dist\native-build.log:' + [Environment]::NewLine + $native.Text)
}
Copy-Item -LiteralPath 'dist/L4D2Minecraft.dll' -Destination 'dist/L4D2Minecraft.addon32'
python -c "import pefile; p=pefile.PE('dist/L4D2Minecraft.addon32'); assert p.FILE_HEADER.Machine == 0x14c; assert b'AddonInit' in [e.name for e in p.DIRECTORY_ENTRY_EXPORT.symbols]; print('Verified x86 PE DLL with AddonInit')"
if ($LASTEXITCODE -ne 0) { throw 'Native binary validation failed' }
$native = Invoke-NativeCapture -Command { & $Zig c++ -target x86-windows-gnu -std=c++17 -O2 passthrough/test_cursor.cpp -o dist/test_cursor.exe -luser32 }
if ($native.ExitCode -ne 0) {
    throw ('Native cursor test build failed (zig exit ' + $native.ExitCode + '):' + [Environment]::NewLine + $native.Text)
}
& '.\dist\test_cursor.exe'
if ($LASTEXITCODE -ne 0) { throw 'Native cursor regression failed' }
python -m unittest discover -s passthrough -p 'test_*.py'
if ($LASTEXITCODE -ne 0) { throw 'Camera tests failed' }

function Invoke-CheckedSquirrel {
    param([string[]]$CheckArguments,[string]$Success='')
    $check = Invoke-SourceProcess -Executable $Squirrel -CheckArguments $CheckArguments -LogPath $sourceLog
    $checkExit = $check.ExitCode
    $checkText = $check.Text
    if($checkText.Trim()){Write-Output $checkText.Trim()}
    if($checkExit -ne 0 -or $checkText -match 'AN ERROR HAS OCCURRED|error [^\r\n]*line' -or ($Success -and !$checkText.Contains($Success))) {
        throw ('Standalone Source verification failed: '+($CheckArguments -join ' ')+'; exit '+$checkExit+' ('+$check.HexCode+'). '+$checkText+' Full diagnostics: dist/source-check.log. VM errors and missing success markers remain fatal.')
    }
}
if (Test-Path -LiteralPath $Squirrel) {
    foreach ($hostScript in Get-ChildItem -LiteralPath 'passthrough/host' -Filter '*.nut') {
        Invoke-CheckedSquirrel -CheckArguments @('-c','-o','dist/syntax-check.cnut',$hostScript.FullName)
    }
    Invoke-CheckedSquirrel -CheckArguments @('passthrough/test_protection.nut') -Success 'Source protection arithmetic passed'
    Invoke-CheckedSquirrel -CheckArguments @('passthrough/test_surfaces.nut') -Success 'Retail floor/nav and shield capacity regressions passed'
    Invoke-CheckedSquirrel -CheckArguments @('passthrough/test_weapon_visibility.nut') -Success 'Third-person weapon and drop visibility regressions passed'
    Invoke-CheckedSquirrel -CheckArguments @('passthrough/test_native_use.nut') -Success 'Native checkpoint press/hold and carry-drop regressions passed'
    Invoke-CheckedSquirrel -CheckArguments @('passthrough/test_team_export.nut') -Success 'Teammate alpha HUD source export regressions passed'
    Invoke-CheckedSquirrel -CheckArguments @('passthrough/test_golem.nut') -Success 'Source golem one-hit, corpse and wall regressions passed'
    Invoke-CheckedSquirrel -CheckArguments @('passthrough/test_collision_protocol.nut') -Success 'Actual collision/gameplay framing and epoch regressions passed'
    Invoke-CheckedSquirrel -CheckArguments @('passthrough/test_coop.nut') -Success 'Source coop context, callback and manifest regressions passed'
    Invoke-CheckedSquirrel -CheckArguments @('passthrough/test_coop_combat.nut') -Success 'Source peer combat actor, aim and replay regressions passed'
    Invoke-CheckedSquirrel -CheckArguments @('passthrough/test_projectiles.nut') -Success 'Projectile launch/authority regressions passed'
    Invoke-CheckedSquirrel -CheckArguments @('passthrough/test_flight.nut') -Success 'Source Elytra native flight and cleanup regressions passed'
}
