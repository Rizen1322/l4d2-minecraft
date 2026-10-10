# Development and release

Source owns movement/health/native actors/map scene; guest owns Minecraft
items/blocks/UI. Python bridges local WebSocket25601, mailboxes and shared memory;
x86 add-on pairs colour/depth/UI with scene/camera.

Optional `coop.py` LANroom relays actor-specific snapshots to each PC. Source
listen host owns the four-survivor contexts; clients never execute server VM
commands. `RoomPath` routes gameplay/collision payloads and pickup/reward outboxes.
Room sockets authenticate a private token, enforce Source scene/actor ownership,
retain deletion tombstones and bound resync/backlogs. Source frame freshness is
tracked independently of packet traffic. See [LAN setup](COOP.md).

Components: `passthrough/host/` gameplay/survival/navigation; `guest/` Fabric;
`bridge.py` transport; `native/` and `shaders/` compositing/cursor; `tools/`
private HUD derivation. Build parameters in INSTALL.md; Java25 required.
Squirrel checks cannot silently skip; zero exit alone insufficient (VM errors
and missing success sentinel fail build). Build does not launch games.

```powershell
python tools/release_source.py --check
python tools/release_source.py
```

Produces `release/l4d2-minecraft-alpha-source.zip`, SHA256 and embedded manifest.
Allowlist excludes game/build/profile paths and common credential/private-key
formats; this does not establish arbitrary legal/security compliance.
Do not attach private JAR/HUD VPK, ReShade, worlds or toolchains.

GitHub target: https://github.com/Rizen1322/l4d2-minecraft . Upload/release remains
a separate final action after reviewing prepared files and known limitations.
