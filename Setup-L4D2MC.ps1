param([Parameter(Mandatory=$true)][string]$Game,
      [Parameter(Mandatory=$true)][string]$Minecraft,
      [Parameter(Mandatory=$true)][string]$ReShadeDll,
      [string]$JavaHome=$env:JAVA_HOME, [string]$Zig='', [string]$ReShadeInclude='', [string]$Squirrel='')
$ErrorActionPreference='Stop'
Set-Location -LiteralPath $PSScriptRoot
if (Get-Process left4dead2 -ErrorAction SilentlyContinue) { throw 'Close L4D2 before setup. No processes will be stopped automatically.' }
if (!(Test-Path -LiteralPath (Join-Path $Game 'left4dead2.exe'))) { throw 'L4D2 executable missing.' }
if (!(Test-Path -LiteralPath $ReShadeDll)) { throw 'Supply the official add-on-enabled x86 ReShade DLL.' }
& python -c "import sys; sys.path.insert(0,'passthrough'); from install import validate_reshade; validate_reshade(sys.argv[1])" $ReShadeDll
if ($LASTEXITCODE -ne 0) { throw 'Loader preflight failed; nothing installed. Supply the official x86 add-on ReShade DLL.' }
$localConfig=Join-Path $PSScriptRoot 'l4d2mc.local.json'
$paths=@{game=[IO.Path]::GetFullPath($Game);minecraft=[IO.Path]::GetFullPath($Minecraft)}
$paths | ConvertTo-Json | Set-Content -LiteralPath $localConfig -Encoding UTF8
& (Join-Path $PSScriptRoot 'passthrough/build.ps1') -Game $Game -JavaHome $JavaHome -Zig $Zig -ReShadeInclude $ReShadeInclude -Squirrel $Squirrel
$loader=Join-Path $PSScriptRoot 'toolchains/ReShade32.dll'
New-Item -ItemType Directory -Path (Split-Path $loader -Parent) -Force | Out-Null
if (!(Test-Path -LiteralPath $loader) -or (Get-FileHash -LiteralPath $loader).Hash -ne (Get-FileHash -LiteralPath $ReShadeDll).Hash) {
    Copy-Item -LiteralPath $ReShadeDll -Destination $loader
}
& python passthrough/install.py host --game $Game --minecraft $Minecraft
if ($LASTEXITCODE -ne 0) { throw 'Host installation failed; existing unowned loaders are preserved.' }
& python passthrough/install.py guest --game $Game --minecraft $Minecraft
if ($LASTEXITCODE -ne 0) { throw 'Guest profile installation failed.' }
& python passthrough/update.py --game $Game
if ($LASTEXITCODE -ne 0) { throw 'Component verification failed.' }
Write-Output 'Setup complete. Launch L4D2MC-Fabric-26.3 with your normal signed-in launcher, then Launch-L4D2MC-2K.bat. No games were started.'
