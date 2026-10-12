# L4D2MC 2.0.11

Download **L4D2MC-Companion.exe**, select RU / EN, open Setup and use **Update and install** on both PCs with Minecraft and L4D2 closed. Launch the Minecraft profile through your normal launcher, then use Play. For co-op, the host creates an invitation and the friend enters their own L4D2 nickname. [Installation guide](https://github.com/Rizen1322/l4d2-minecraft/blob/master/docs/INSTALL.md).

This is a normal GitHub release of the EXE and source package. **Co-op is still experimental and needs more work.** Valid but outdated map mailboxes are discarded without closing the socket. Temporary Windows file contention no longer tears down the room while writing Source mailboxes, collision/session manifests or guest pose/status files: fresh snapshots retry the write. A congested Minecraft mob owner no longer disconnects the player hitting it. Reliable events wait for capacity, preserve order and avoid duplicate accepted damage while camera updates continue. Four new loopback regressions check these failures and recovery on the same socket; the complete Python suite has 151 tests. Genuine network loss and Source stalls can still interrupt play.

Includes the 2.0.10 improvements: hold RMB to revive a downed teammate or help one hanging from a ledge. Downed Steve lies prone, the helper has a two-handed animation and a temporary third-person camera that restores the previous view. Looking away within rescue range keeps use held. Survivor bots can engage hostile Minecraft mobs; Tank attacks send guest knockback and request native punch input.

During rescue, Steve faces the teammate while the camera can turn freely. The action bar uses Source's actual progress timer and is drawn in the final Minecraft GUI layer above Steve.

Known limits: intermittent co-op interruptions, fast-motion reprojection holes, special-infected interactions and incomplete mob abilities. Some grass, bottles and other props can still draw over Minecraft in late Source material passes. A fresh two-PC visual/audio regression is pending; automated tests are not proof of complete gameplay correctness.

Windows 10/11, .NET Framework 4.8, Steam L4D2, Minecraft Java 26.3 / Java 25, official L4D2 Authoring Tools. The EXE is unsigned. Public downloads contain source and companion only; game-derived JAR/HUD, worlds, configs, credentials and toolchains are excluded. SHA-256 files accompany both assets.
