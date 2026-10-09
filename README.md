# Minecraft inside Left 4 Dead 2

**Experimental Windows source release.** Real Minecraft runs alongside L4D2.
Source supplies the map, movement and infected; Minecraft supplies blocks,
items, inventory, mobs and Steve. A local bridge and x86 ReShade add-on composite
Minecraft's colour/depth/UI into L4D2. This is an independent fan project.

## What is implemented

- Place and break Minecraft blocks on Source maps, with bounded collision proxies.
- Minecraft inventory/hotbar; Source walking/jumping and Source Escape menu.
- Swords with cleave, shields/cooldown, armour, food and health sync.
- TNT, flint-and-steel fire, ender pearls, chorus fruit and held totems.
- Iron golems targeting infected, plus native navigation/collision queries.
- L4D2 pickups converted to Minecraft supplies; durable reward/item receipts.
- Scene isolation on map changes/restarts; teammate cards above the full shield.

Implemented mechanics do **not** mean every item or map is fully supported.
Recent fixes passed offline tests; full runtime revalidation is pending.
See [known issues](docs/KNOWN_ISSUES.md).

## Requirements

| Component | Tested target |
|---|---|
| Host | Windows, Steam L4D2, local `-insecure` session |
| Guest | Minecraft Java26.3, Java25, Fabric0.19.5, Fabric API0.161.0+26.3 |
| Renderer | Direct3D9, x86 ReShade6.8.0 with full add-on support |
| Build | Python3.12+, Zig0.15.2, ReShade6.8 SDK headers, Squirrel3.2 compiler |
| Private HUD build | Official L4D2 Authoring Tools (`vpk.exe`) |

Use your own copies of both games and a normal signed-in Minecraft launcher.
The repository/ZIP does not contain either game, ReShade, saves, launcher
credentials or privately extracted HUD assets. Distribution is source-only:
compiled guest JARs contain private portraits and must not be uploaded.

## Setup and launch

1. Install requirements from official sources, then Python packages:
   `python -m pip install -r requirements.txt`.
2. Close both games. Run [Setup-L4D2MC.ps1](Setup-L4D2MC.ps1) with your game,
   launcher and tool paths. It builds/checks/installs owned files without launching
   games. [Exact commands and tool links](docs/INSTALL.md).
3. In your Minecraft launcher, select **L4D2MC-Fabric-26.3** and launch normally.
   Use its private guest world; keep Minecraft rendering behind L4D2.
4. Run **Launch-L4D2MC-2K.bat** for2560×1440 borderless, or
   `Launch-Minecraft.ps1 -Width 1920 -Height 1080 -Borderless`.
   Keep the launch console open until exit so temporary controls restore.

The launcher applies built updates before starting L4D2. A locked native add-on
requires exiting L4D2 first. Steam library detection is automatic; explicit
`-Game`, `L4D2MC_GAME`, or ignored `l4d2mc.local.json` overrides it. Custom
Minecraft launcher directories use `L4D2MC_MINECRAFT` or the same local config.

## Controls

| Input | Action |
|---|---|
| WASD / Space | L4D2 movement / jump |
| Left mouse | Minecraft attack / break |
| Right mouse | Minecraft use/place; Source doors/buttons/carry interactions |
| E | Minecraft inventory |
| Escape | Source pause menu; closes guest UI first |
| 1–9 / wheel | Hotbar |
| Q / F | Drop / swap hands |
| F5 | Camera perspective |
| T / / | Minecraft chat / command |

## Development and release

`passthrough/build.ps1` runs guest/native x86 builds, a real hidden-window cursor
regression, Python tests and standalone Source suites. No games launch during
these checks. See [development guide](docs/DEVELOPMENT.md).

`python tools/release_source.py --check` audits the allowlisted source payload.
`python tools/release_source.py` creates a reproducible ZIP with SHA256 and per-file
manifest. It excludes builds, extracted assets, profiles and common credentials.

[Changelog](CHANGELOG.md) · [Troubleshooting / uninstall](docs/TROUBLESHOOTING.md)
· [Credits and AI disclosure](CREDITS.md) · [MIT license](LICENSE)

The earlier cube experiment remains in `addon/` and `assets-src/` as history.
The active mashup still uses its own generated cube for native collisions;
the ZIP includes its procedural source generator, not precompiled model files.
