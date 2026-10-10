# Capture the compiler's own process exit code, independent of PowerShell scopes
# and LASTEXITCODE left over from Python/Gradle/native calls.
function Invoke-SourceProcess {
    param([string]$Executable,[string[]]$CheckArguments,[string]$LogPath)
    $start=[Diagnostics.ProcessStartInfo]::new()
    $start.FileName=[IO.Path]::GetFullPath($Executable)
    $start.WorkingDirectory=(Get-Location).Path
    $start.Arguments=($CheckArguments | ForEach-Object {'"'+$_.Replace('"','\"')+'"'}) -join ' '
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    $process=[Diagnostics.Process]::new();$process.StartInfo=$start
    try {
        $null=$process.Start()
        $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
        if(!$process.WaitForExit(60000)){$process.Kill();throw 'Squirrel compiler timed out after60seconds.'}
        $result=@{ExitCode=$process.ExitCode;Text=($stdout.Result+$stderr.Result)}
    } finally {$process.Dispose()}
    $bits=[BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$result.ExitCode),0)
    $result.HexCode=('0x{0:X8}' -f $bits)
    $record=('Squirrel: '+$start.FileName+' '+$start.Arguments+[Environment]::NewLine+
        'Exit: '+$result.ExitCode+' ('+$result.HexCode+')'+[Environment]::NewLine+$result.Text)
    if($LogPath){Add-Content -LiteralPath $LogPath -Value $record -Encoding UTF8}
    return $result
}
