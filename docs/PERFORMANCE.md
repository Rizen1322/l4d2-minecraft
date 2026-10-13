# Performance notes

The mod runs two renderers, a Minecraft integrated server and a bridge. These are code-level findings, not a measured FPS benchmark. Games were not launched for this audit at the author's request.

## Presets in the companion

Play → Minecraft performance. Source keeps the width/height selected above it; only the private Minecraft guest changes size and frame cap. Settings are independent on each PC.

| Preset | Minecraft at 2560×1440 Source | Guest frame cap | Four-layer payload per frame |
|---|---:|---:|---:|
| Quality (existing default) | 2560×1440 | Unlimited | 56.25 MiB |
| Balanced | 1920×1080 | 90 FPS | 31.64 MiB |
| Low-end PC | 1280×720 | 60 FPS | 14.06 MiB |

Payload is width × height × four layers × four bytes, excluding metadata. Each image travels from the Minecraft GPU into CPU/shared memory and is uploaded into Source textures. Low reduces pixels and payload per frame by 75%; this is **not** a claim of 75% more FPS. Shared-memory maximum capacity and Minecraft's configured Java heap remain unchanged.

Lower presets soften Minecraft/UI pixels and increase frame age during fast movement. Use Quality if edges or camera motion look worse. The four-layer protocol, source camera aspect, health, collision and input timing are unchanged. Inventory coordinates remain normalized.

Low-end PC also suppresses guest contact shadows, bloom and edge smoothing via frame flag bit 8. Lighting and depth visibility remain enabled; Quality/Balanced retain the original cosmetic settings. The flag is captured with each frame so in-flight readbacks cannot mix profile settings.

Manual launch: `Launch-Minecraft.ps1 -Width 2560 -Height 1440 -Borderless -Performance low`. Other values: `balanced`, `quality`. Restart the bridge to change presets. The guest frame limit is applied at runtime without rewriting Minecraft's saved graphics options.

## Main hotspots in the current code

1. **Frame export/upload:** `FrameExporter.java` captures world, depth, hands and GUI every Minecraft frame. Quality has uncapped rendering. Resolution and frame cap have the largest obvious effect on this traffic and guest GPU work. Copies are already asynchronous/ring-buffered; the native upload already streams from shared memory without an extra full image staging copy.
2. **Full-resolution reprojection:** `L4D2Minecraft.fx` runs at Source resolution. During translation it still marches 24 depths and refines a candidate up to 12 times. The logarithmic schedule now uses one exponentiation and repeated multiplication; rotated rays are computed once rather than reconstructed inside both loops. The last sample stays pinned to the original far bound. A valid tracked surface still searches nearer surfaces to avoid incorrect visibility. Reducing these limits blindly can bring back disappearing blocks. This remains a GPU profiling target.
3. **Collision scan:** `WorldBridge.sync(16)` covers 33×33×65 = 70,785 cells about four times per second. It now skips exact empty chunk sections. A complete stationary snapshot is reused for less than one second; block edits, bounds changes, scene/server changes and unavailable chunks invalidate reuse. Loaded availability is checked even on cache hits. Dynamic-shape blocks and block entities disable snapshot reuse because collision can animate without a state write. The full replacement bounds, solid predicate, unavailable-chunk abort and overflow abort remain intact. Dense changing builds still require work.
4. **Lighting and post-processing:** hidden/empty Minecraft pixels now bypass relighting, grading and haze reads. Empty bloom pixels also avoid a composite fetch. Contact shadows sample ten neighbours; edge smoothing and bloom add more reads. These costs still run at Source resolution.
5. **Entity work:** load/unload indexes replace per-tick whole-world scans for player projectiles and brain mobs. A single bootstrap scan handles entities loaded before bridge attachment; resets/unloads clear membership and protect reused IDs. Nearby mob reporting uses stable nearest-64 selection, calculating distance once per candidate instead of sorting all candidates. Updates retain their original cadence so pearls and attacks are not deliberately delayed. Mob AI itself still consumes CPU.
6. **Source navigation:** each navigation job slice allows 16 expansions and 64 neighbours, with multiple traces per portal. Static navmesh corners now use a bounded 2048-area cache; actual floor/portal traces and dynamic blocking checks remain live. It rotates jobs fairly, but persistent routes across several co-op contexts can still consume Source CPU time. Cutting the budget can worsen golem stalls.
7. **Bridge/file traffic:** the fast local bridge avoids reparsing unchanged Source JSON by checking file metadata, with a forced read within 100 ms for coarse metadata. Only actual frame changes renew the pose lease. Changed files are read immediately. Source/co-op export cadence and stale-control expiry remain unchanged. Per-mob formatting and co-op file work remain CPU profiling candidates.

## Verification

The Python tests cover preset dimensions, aspect ratio, bounds and unchanged Quality defaults. The real PowerShell argument regression covers passing the profile through Unicode/space-containing paths. Full Fabric/native/Source builds and companion tests pass; RU/EN EXE layout was rendered and inspected.

Additional checks cover cache invalidation, entity ID reuse/unload, stable nearest-64 selection against a full sort, one distance evaluation per candidate, frozen-pose expiry/coarse file metadata, live Source portal traces despite cached corners and a float32 numerical reference of the 24-sample schedule. That reference does not compile or execute the ReShade shader.

Actual FPS, frametime percentiles, shader compilation in ReShade, fast turns, inventory, projectile/collision correctness and both-PC performance still need a repeatable in-game comparison. Compare the same map, camera path, block/mob count and Source resolution; record Minecraft and Source frame times separately. No weaker-PC hardware minimum has been established.
