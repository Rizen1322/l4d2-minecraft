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
