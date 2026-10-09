$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $projectRoot
$env:JAVA_HOME = 'C:\Users\Rizen\AppData\Roaming\.tlauncher\legacy\Minecraft\jre\java-runtime-epsilon\windows-x64\java-runtime-epsilon'
& '.\passthrough\guest\gradlew.bat' -p '.\passthrough\guest' build --no-daemon
if ($LASTEXITCODE -ne 0) { throw 'Guest build failed' }
# ReShade is built with MSVC. Its x86 member functions return small handle
# structs through a hidden pointer. compositor.cpp contains the explicit ABI wrapper.
& '.\toolchains\zig-x86_64-windows-0.15.2\zig.exe' c++ -target x86-windows-gnu -std=c++17 -O2 -shared -I toolchains/reshade-6.8.0/include passthrough/native/addon.cpp passthrough/native/compositor.cpp -o dist/L4D2Minecraft.dll -luser32
if ($LASTEXITCODE -ne 0) { throw 'Native build failed' }
Copy-Item -LiteralPath 'dist/L4D2Minecraft.dll' -Destination 'dist/L4D2Minecraft.addon32'
python -c "import pefile; p=pefile.PE('dist/L4D2Minecraft.addon32'); assert p.FILE_HEADER.Machine == 0x14c; assert b'AddonInit' in [e.name for e in p.DIRECTORY_ENTRY_EXPORT.symbols]; print('Verified x86 PE DLL with AddonInit')"
if ($LASTEXITCODE -ne 0) { throw 'Native binary validation failed' }
python -m unittest discover -s passthrough -p 'test_*.py'
if ($LASTEXITCODE -ne 0) { throw 'Camera tests failed' }

function Invoke-CheckedSquirrel {
    param([string[]]$CheckArguments,[string]$Success='')
    $checkOutput = & './toolchains/squirrel-parser/sq.exe' @CheckArguments 2>&1
    $checkExit = $LASTEXITCODE
    $checkText = ($checkOutput | Out-String)
    if($checkText.Trim()){Write-Output $checkText.Trim()}
    if($checkExit -ne 0 -or $checkText -match 'AN ERROR HAS OCCURRED|error [^\r\n]*line' -or ($Success -and !$checkText.Contains($Success))) {
        throw 'Standalone Source verification failed (including VM errors with zero exit status).'
    }
}
if (Test-Path -LiteralPath 'toolchains/squirrel-parser/sq.exe') {
    foreach ($hostScript in Get-ChildItem -LiteralPath 'passthrough/host' -Filter '*.nut') {
        Invoke-CheckedSquirrel -CheckArguments @('-c','-o','dist/syntax-check.cnut',$hostScript.FullName)
    }
    Invoke-CheckedSquirrel -CheckArguments @('passthrough/test_protection.nut') -Success 'Source protection arithmetic passed'
    Invoke-CheckedSquirrel -CheckArguments @('passthrough/test_surfaces.nut') -Success 'Retail floor/nav and shield capacity regressions passed'
    Invoke-CheckedSquirrel -CheckArguments @('passthrough/test_collision_protocol.nut') -Success 'Actual collision/gameplay framing and epoch regressions passed'
}
