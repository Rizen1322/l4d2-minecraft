# Installation with L4D2MC Companion

Use your own Steam L4D2 and Minecraft Java26.3. Local experimental mod: launcher
uses `-insecure`, not public protected matchmaking. Use its private guest world.

## Recommended: the Windows EXE

1. Download **L4D2MC-Companion.exe** from [Releases](https://github.com/Rizen1322/l4d2-minecraft/releases). Keep it in a permanent folder; administrator rights are normally unnecessary.
2. Choose **RU / EN**. Open **Setup** and check the three paths: a separate project directory, L4D2's directory containing `left4dead2.exe`, and your launcher's Minecraft directory containing `versions/`.
3. Install the target vanilla Minecraft **Java 26.3** through your normal launcher once. The app never asks for your Minecraft password.
4. Click **Authoring Tools** to install Steam AppID 563. Wait for Steam to finish. Close Minecraft and L4D2; the launcher can stay open.
5. Click **Update and install**. It downloads the newest source release, checks SHA-256 and its manifest, prepares tools privately, builds/tests and installs. First setup can take several minutes. Progress is per download, not a total installation estimate.
6. Wait for completion. If anything fails, open **Log** and use **Open log file**. Fix the reported problem and retry; tools already downloaded can be reused.
7. Open **Play**, launch **L4D2MC-Fabric-26.3** through your normal launcher, and wait for Minecraft to enter its private world. Refresh the version list if needed.
8. Choose resolution and a solo/host map, then click **Start the mashup**. The default is borderless 2560×1440. Joining players use their saved host session rather than their map selection. Leave the app open. Close L4D2 normally to stop the bridge and restore its settings.

## Co-op through the app

Both PCs need the same release, their own games and a shared LAN/VPN network. The app does not install a VPN or configure the router.

- **Host:** Co-op → choose the LAN/VPN address → Create and copy invitation. Send that invitation privately to your friend. Launch Minecraft, then the mashup, and enter the map.
- **Friend:** paste the invitation and enter **your own L4D2 nickname**, not the host's nickname. Save the connection. Launch Minecraft, then the mashup. Your L4D2 joins the host automatically.
- Keep nicknames distinct. Allow the game/bridge on the appropriate private network if Windows asks. The room uses TCP 25602; the native game usually uses port 27015.
- Use **Return to solo mode** when playing alone. Updating preserves room settings, so an old join configuration otherwise remains active.

## Updates

Version 2.0.12 adds **Play → Minecraft performance**. Choose Balanced or Low-end PC to lower only the guest renderer's resolution and frame cap; Quality preserves the previous defaults. See [performance notes](PERFORMANCE.md). Each PC can choose its own preset.

Close both games, open Setup and click **Update and install** on both PCs. This updates source and rebuilds the installed components in one action. **Download / update project** only changes source; it does not install the new guest/native binaries. Restart Minecraft and the bridge afterward. Download a newer companion EXE from Releases when the app itself changes; it does not replace its own executable.

The project folder must stay in place because the Minecraft profile references it. Private world data and co-op settings are preserved. Source files are replaced: use a separate checkout for development changes. The EXE is unsigned; checksums confirm downloaded bytes, not a publisher certificate.

## Advanced: manual source setup

The commands below are for developers or custom tool installations. Ordinary EXE users do not need to run them.

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
