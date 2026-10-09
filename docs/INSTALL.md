# Installation (Windows, source build)

Use your own Steam L4D2 and Minecraft Java26.3. Local experimental mod: launcher
uses `-insecure`, not public protected matchmaking. Use its private guest world.

## Official tools

- Java25, Python3.12+ and a working signed-in Minecraft launcher.
- [Fabric](https://fabricmc.net/) metadata/API are fetched by guest installer.
- [ReShade6.8.0](https://reshade.me/) full add-on support, x86 DLL and
  [SDK headers](https://github.com/crosire/reshade/tree/v6.8.0/include).
- [Zig0.15.2](https://ziglang.org/download/) on PATH or supplied executable.
- [Squirrel3.2](https://github.com/albertodemichelis/squirrel/releases) standalone
  sq.exe built from official source (CMake/compiler if no suitable binary).
- L4D2 Authoring Tools: Steam Library → Tools; game `bin/vpk.exe` and
  `bin/studiomdl.exe` required. The source build generates its own collision cube.

Toolchains are not redistributed. Gradle downloads its declared dependencies.
Setup fetches official Minecraft/Fabric metadata and Fabric API; credentials
remain in your launcher.

## Setup entry point

From extracted repository, in PowerShell:

```powershell
python -m pip install -r requirements.txt
.\Setup-L4D2MC.ps1 `
  -Game 'D:\SteamLibrary\steamapps\common\Left 4 Dead 2' `
  -Minecraft "$env:APPDATA\.minecraft" `
  -ReShadeDll 'D:\ModTools\ReShade32.dll' `
  -JavaHome 'D:\ModTools\jdk-25' `
  -Zig 'D:\ModTools\zig\zig.exe' `
  -ReShadeInclude 'D:\ModTools\reshade-6.8.0\include' `
  -Squirrel 'D:\ModTools\squirrel\sq.exe'
```

`-Minecraft` is the launcher's directory containing `versions/`. Custom launchers
require their actual directory. ReShade DLL must be add-on-enabled32-bit.
Existing unowned loaders are refused. Setup stores paths in ignored
`l4d2mc.local.json`; preserve receipt `backups/passthrough-install.json` for removal.
Do not move checkout after installing: guest profile references its directory.

Select `L4D2MC-Fabric-26.3` in normal launcher, refresh versions if needed, launch
Minecraft, then `Launch-L4D2MC-2K.bat`. Other resolutions/maps:

```powershell
.\Launch-Minecraft.ps1 -Width 1920 -Height 1080 -Borderless -Map c2m1_highway
```

Keep launch console open until exit so bindings/addon flags restore. Exit L4D2
before native updates. This setup was verified offline; clean-machine end-to-end
installation remains pending.
