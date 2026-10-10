# Packs the source tree plus the local open-source toolchains into one ZIP for a
# teammate who owns both games. Excludes builds, private HUD/portrait assets,
# saves, logs, local paths and the private co-op room token.
param([string]$Output='')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if(!$Output){$Output=Join-Path $root 'release\l4d2mc-friend.zip'}
$staging=Join-Path ([IO.Path]::GetTempPath()) ('l4d2mc-friend-'+[guid]::NewGuid().ToString('N'))
$target=Join-Path $staging 'l4d2-minecraft'
New-Item -ItemType Directory -Path $target -Force | Out-Null
try{
    # Robocopy excludes bare names at EVERY depth, case-insensitively. Excluding
    # "build" removed Zig's lib/std/Build and produced an unusable compiler.
    $excludeDirs=@('.git','backups','evidence','build-game','dist','output','release','research','build','run') |
        ForEach-Object { Join-Path $root $_ }
    $excludeDirs+=@('passthrough/guest/.gradle','passthrough/guest/build','passthrough/guest/run',
        'passthrough/guest-game','passthrough/native/build') | ForEach-Object { Join-Path $root $_ }
    $excludeDirs+='__pycache__'
    $excludeFiles=@('l4d2mc.local.json','l4d2mc.coop.json','l4d2mc.coop.json.tmp','*.log','events.jsonl','.env','.env.*',
        'zig.zip','ReShade64.dll','ReShade_Setup_*.exe','*.pdb')
    & robocopy $root $target /E /NFL /NDL /NJH /NJS /NP /XD @excludeDirs /XF @excludeFiles | Out-Null
    if($LASTEXITCODE -ge 8){throw 'robocopy failed'}
    foreach($private in @('l4d2mc.local.json','l4d2mc.coop.json')){
        if(Test-Path -LiteralPath (Join-Path $target $private)){throw "Private file leaked into package: $private"}
    }
    foreach($zigPart in @('Cache.zig','Fuzz.zig','Module.zig','Step.zig','Watch.zig','WebServer.zig','abi.zig')) {
        $relative='toolchains/zig-x86_64-windows-0.15.2/lib/std/Build/'+$zigPart
        if(!(Test-Path -LiteralPath (Join-Path $target $relative))) {
            throw ('Incomplete Zig toolchain in package: '+$relative)
        }
    }
    New-Item -ItemType Directory -Path (Split-Path $Output -Parent) -Force | Out-Null
    if(Test-Path -LiteralPath $Output){Remove-Item -LiteralPath $Output}
    Compress-Archive -Path $target -DestinationPath $Output -CompressionLevel Optimal
    $hash=(Get-FileHash -LiteralPath $Output).Hash
    Write-Output ("{0}  {1:N0} MB  SHA256 {2}" -f $Output,((Get-Item $Output).Length/1MB),$hash)
} finally {
    $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    $resolvedStaging=[IO.Path]::GetFullPath($staging)
    if(!$resolvedStaging.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path $resolvedStaging -Leaf) -notlike 'l4d2mc-friend-*') { throw 'Unsafe temporary cleanup target.' }
    Remove-Item -LiteralPath $resolvedStaging -Recurse -Force -ErrorAction SilentlyContinue
}
