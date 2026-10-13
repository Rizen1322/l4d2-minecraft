$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$probeRoot = Join-Path ([IO.Path]::GetTempPath()) ('l4d2mc argv ' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($probeRoot) > $null
$bridgeScript = Join-Path $probeRoot 'bridge probe.py'
$coopPath = Join-Path $probeRoot 'room config.json'
$stdout = Join-Path $probeRoot 'stdout.txt'
$stderr = Join-Path $probeRoot 'stderr.txt'
try {
    [IO.File]::WriteAllText($bridgeScript, 'import sys,json; print(json.dumps(sys.argv[1:],ensure_ascii=True))', [Text.Encoding]::ASCII)
    [IO.File]::WriteAllText($coopPath, '{}', [Text.Encoding]::ASCII)
    $Game = Join-Path $taskRoot 'fake game path'
    $playCfgName = 'play_probe'
    $restoreCfgName = 'restore_probe'
    $Width = 2560
    $Height = 1440
    $Performance = "low"
    $lines = Get-Content -LiteralPath (Join-Path $taskRoot 'Launch-Minecraft.ps1')
    # Exercise the real launcher's argument expressions through Start-Process.
    $assignment = @($lines | Where-Object { $_ -match '^\s*\$bridgeArguments = ' })
    $coopAssignment = @($lines | Where-Object { $_ -match '^\s*if .*\$bridgeArguments \+=' })
    if ($assignment.Count -ne 1 -or $coopAssignment.Count -ne 1) { throw 'Launcher argument expressions not found.' }
    Invoke-Expression $assignment[0]
    Invoke-Expression $coopAssignment[0]
    $pythonExe = (Get-Command python.exe).Source
    $process = Start-Process -FilePath $pythonExe -ArgumentList $bridgeArguments -WorkingDirectory $taskRoot -WindowStyle Hidden -PassThru -Wait -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    if ($process.ExitCode -ne 0) { throw ([IO.File]::ReadAllText($stderr)) }
    $actual = Get-Content -LiteralPath $stdout -Raw | ConvertFrom-Json
    $expected = @('--game', $Game, '--play-cfg', $playCfgName, '--restore-cfg', $restoreCfgName, '--width', '2560', '--height', '1440', '--performance', 'low', '--coop-config', $coopPath)
    if ($actual.Count -ne $expected.Count) { throw ('Wrong argument count: ' + $actual.Count) }
    for ($i = 0; $i -lt $expected.Count; $i++) {
        if ($actual[$i] -cne $expected[$i]) { throw ('Wrong argument at index ' + $i) }
    }
    Write-Output 'Launcher Start-Process argv regression passed (spaces, Unicode workspace, co-op config).'
} finally {
    foreach ($path in @($bridgeScript, $coopPath, $stdout, $stderr)) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
    }
    [IO.Directory]::Delete($probeRoot)
}
