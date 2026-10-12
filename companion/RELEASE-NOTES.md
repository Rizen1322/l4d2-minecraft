# L4D2MC 2.0.10

Download **L4D2MC-Companion.exe**, select RU / EN, open Setup and use **Update and install** on both PCs with Minecraft and L4D2 closed. Launch the Minecraft profile through your normal launcher, then use Play. For co-op, the host creates an invitation and the friend enters their own L4D2 nickname. [Installation guide](https://github.com/Rizen1322/l4d2-minecraft/blob/master/docs/INSTALL.md).

This is a normal GitHub release of the EXE and source package. **Co-op is still experimental and needs more work.** Short roster gaps and Source export stalls preserve room membership; stale controls remain disabled. Hold RMB to revive a downed teammate or help one hanging from a ledge. Steve lies down while incapacitated and performs a two-handed help animation while reviving, with an automatic third-person camera that restores the previous view afterward. Looking away within rescue range keeps use held. Survivor bots can engage visible hostile Minecraft mobs while leaving passive mobs and golems alone. Tank attacks send Minecraft mob knockback and request native punch input. Smaller bloom/refraction copies no longer qualify as full-scene composition checkpoints.

During rescue, Steve faces the teammate while the camera can turn freely. The action bar uses Source's actual progress timer and is drawn in the final Minecraft GUI layer above Steve.

Known limits: intermittent co-op interruptions, fast-motion reprojection holes, props/depth ordering on some scenes, special-infected interactions and incomplete mob abilities. A fresh two-PC visual/audio regression is pending; automated tests are not proof of complete gameplay correctness.

Windows 10/11, .NET Framework 4.8, Steam L4D2, Minecraft Java 26.3 / Java 25, official L4D2 Authoring Tools. The EXE is unsigned. Public downloads contain source and companion only; game-derived JAR/HUD, worlds, configs, credentials and toolchains are excluded. SHA-256 files accompany both assets.
