# 🧱 V2 Alpha — co-op, Steve rendering and mob routes

V2 separates moving-player/mob snapshots from reliable combat and building events. Building backlogs no longer hold every newer pose in the same delivery queue. Unassigned attacks get priority, same-session reconnects replace their old socket, and stale snapshots expire even when retransmitted.

Remote Steve/mob positions interpolate without changing authoritative collision. A wider guest capture reduces screen-edge gaps during fast turns without resizing windows. Bridged teammates get an original Steve-shaped native glow; original survivor glow is restored when the bridge stops.

Shield contacts/exhaustion play Minecraft block/break sounds. Sword and golem hits use native slash/club damage with impact force. Golems keep usable routes while recalculating, resume from current progress and wait for pending routes. Generic ground mobs can wander/fight; specials and Tanks can pursue registered Minecraft mobs. Small-obstacle jumping extends to ground fighters.

**Download L4D2MC-Companion.exe below**, choose RU / EN and open Setup / Установка. Update both co-op PCs with both games closed. Launch the Minecraft profile through your normal launcher, then start the bridge/L4D2. Co-op needs LAN/VPN connectivity; the EXE is unsigned. Windows 10/11, .NET Framework 4.8, Steam L4D2, Minecraft Java 26.3/Java 25 and official L4D2 Authoring Tools remain required.

Validation: 137 Python tests, Java motion/policy tests, native x86/cursor checks, 11 Source suites, WPF build/tests and a retail L4D2 glow/damage API probe. ReShade compiled the new shader in-game. A fresh two-PC flight/combat run and visual/audio confirmation remain pending. Interpolation cannot eliminate latency; reprojection cannot recover previously hidden surfaces. Flying/water mobs, bosses and special pin animations against guest mobs remain incomplete. [V2 details](https://github.com/Rizen1322/l4d2-minecraft/blob/master/docs/V2.md).

Public assets contain the companion and source only. Game-derived JAR/HUD assets, worlds, private configs and downloaded toolchains are excluded. SHA-256 files accompany both downloads.
