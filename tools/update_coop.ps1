# Update an already installed mashup; never starts or closes either game.
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $taskRoot
if (!(Test-Path -LiteralPath 'backups/passthrough-install.json')) {
    throw 'Run Auto-Setup-L4D2MC first. This updater is for an existing installation.'
}
if (!$env:JAVA_HOME -or !(Test-Path -LiteralPath (Join-Path $env:JAVA_HOME 'bin/java.exe'))) {
    $legacyJava = Join-Path $env:APPDATA '.tlauncher/legacy/Minecraft/jre/java-runtime-epsilon/windows-x64/java-runtime-epsilon'
    $javaCommand = Get-Command java.exe -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath (Join-Path $legacyJava 'bin/java.exe')) { $env:JAVA_HOME = $legacyJava }
    elseif ($javaCommand) { $env:JAVA_HOME = Split-Path (Split-Path $javaCommand.Source -Parent) -Parent }
    else { throw 'Java 25 not found. Run Auto-Setup-L4D2MC to configure it.' }
}
Write-Host 'Building and testing the updated Minecraft mod. No games will be started.'
& './passthrough/guest/gradlew.bat' -p './passthrough/guest' build --no-daemon --max-workers=2
if ($LASTEXITCODE -ne 0) { throw 'Minecraft mod build/check failed.' }
& python -m unittest discover -s passthrough -p 'test_*.py'
if ($LASTEXITCODE -ne 0) { throw 'Bridge/network regression checks failed.' }
. './passthrough/source_checks.ps1'
$squirrel = Join-Path $taskRoot 'toolchains/squirrel-parser/sq-win32.exe'
if (!(Test-Path -LiteralPath $squirrel)) { throw 'Squirrel checker missing. Run Auto-Setup-L4D2MC first.' }
foreach ($sourceFile in (Get-ChildItem -LiteralPath 'passthrough/host' -Filter '*.nut')) {
    $check = Invoke-SourceProcess -Executable $squirrel -CheckArguments @('-c','-o','dist/coop-syntax.cnut',$sourceFile.FullName)
    if ($check.ExitCode -ne 0 -or $check.Text -match 'AN ERROR HAS OCCURRED|CALLSTACK') { throw ('Source script check failed: ' + $check.Text) }
}
foreach ($testFile in (Get-ChildItem -LiteralPath 'passthrough' -Filter 'test_*.nut')) {
    $check = Invoke-SourceProcess -Executable $squirrel -CheckArguments @($testFile.FullName)
    if ($check.ExitCode -ne 0 -or $check.Text -match 'AN ERROR HAS OCCURRED|CALLSTACK') { throw ('Source regression failed: ' + $check.Text) }
}
& python passthrough/update.py
if ($LASTEXITCODE -ne 0) { throw 'Install/update failed. Close the games and rerun this updater.' }
Write-Host 'Update checked. Restart the bridge and both games on BOTH PCs to use the new protocol.'
