# L4D2MC 2.0.12 ⚡

Download **L4D2MC-Companion.exe**, select RU / EN, open Setup and use **Update and install** on both PCs with Minecraft and L4D2 closed. Launch the Minecraft profile through your normal launcher, then use Play. The host creates a co-op invitation; the friend enters their own L4D2 nickname. [Installation guide](https://github.com/Rizen1322/l4d2-minecraft/blob/master/docs/INSTALL.md).

## Choose the guest renderer's workload

Play now offers three Minecraft performance presets, independently on each PC:

| Preset | Minecraft dimensions | Guest frame cap |
| --- | --- | --- |
| Quality — existing default | 100% of Source | Uncapped (260 sentinel) |
| Balanced | 75% | 90 FPS |
| Low-end PC | 50% | 60 FPS |

L4D2 keeps its resolution. At 2560×1440, Low renders Minecraft at 1280×720: 75% fewer guest pixels and frame payload bytes. This is a workload reduction, **not a measured FPS improvement**. Lower presets soften Minecraft, including its UI, and can increase frame age. Low also skips cosmetic bloom, contact shadows and edge smoothing while retaining lighting and depth checks. [Performance notes](https://github.com/Rizen1322/l4d2-minecraft/blob/master/docs/PERFORMANCE.md).

## Less repeated work

- Empty or occluded Minecraft pixels skip unnecessary lighting and effect samples. Reprojection retains all 24 search steps and 12 refinements, with invariant arithmetic moved out of the loops.
- Collision scanning skips empty chunk sections. Complete stationary snapshots can be reused briefly; edits, movement, missing chunks and scene changes invalidate the cache. Dynamic shapes and block entities prevent reuse.
- Loaded projectile and mob indexes replace repeated whole-world scans. Stable nearest-64 selection avoids sorting every reported mob.
- Source navigation caches static area corners while keeping blockage and geometry traces live. Unchanged Source JSON has bounded parse reuse without extending frozen-pose freshness.

## Checks and limits

158 Python tests, Java/Fabric build and policy checks, native checks, 11 Source suites, and the RU/EN companion build/tests passed. **Games were not launched for this release at the author's request.** Runtime shader compilation, FPS/frametime measurements and live collision/visual checks are pending.

This is a normal release of the EXE and source package. **Co-op remains experimental.** Intermittent network interruptions, fast-motion reprojection holes and some grass/bottle/late-material render order issues are still possible. This release does not claim to fix every rendering issue.

Windows 10/11, .NET Framework 4.8, Steam L4D2, Minecraft Java 26.3 / Java 25, official L4D2 Authoring Tools. The EXE is unsigned. Downloads exclude game-derived JAR/HUD, worlds, private configs, credentials and toolchains. Both assets have SHA-256 files.
