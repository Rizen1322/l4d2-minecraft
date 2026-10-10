# Known issues

- Two-process experiment, Windows/D3D9/x86 host. Experimental LAN co-op has
  loopback/Source-handler tests; a complete two-PC gameplay test is pending.
  Protected sessions and other Workshop/ReShade mods remain unvalidated.
- Co-op exchanges blocks and render-only remote entities; inventories and
  block-entity NBT are not shared. Remote mob melee hits route to the owning
  Minecraft server; projectile/splash damage against these visual copies is
  not yet supported. Exact mob variants, TNT fuse and projectile NBT are not transmitted.
- Native Elytra velocity physics is new; client prediction, latency and complex
  map geometry still need multiplayer testing. Flight restores Source gravity
  after landing, interruptions or a stale guest lease.
- Retail Source VScript lacks required hull API; bounded rays can miss thin
  surfaces, vehicle edges, slopes and irregular/custom maps.
- Native maps are not destructible voxel worlds. Golems use Source route queries
  with guest collision proxies; not every obstacle/item/entity is fully supported.
- Totem requires active native scene/safe floor. Full-team wipe/Director restart
  may interrupt transaction. Standard co-op armour uses post-damage nonlethal
  refund where pre-damage hook is absent; it cannot prevent every lethal hit.
- Recent cursor, alpha HUD, safedoor, fire/TNT/fall-rescue/input fixes require
  runtime confirmation after restarting games/bridge.
- Locally built JAR/HUD contain private game-derived assets, not public artifacts.
- Camera reprojection/depth remains approximate for unusual views, effects and
  unsupported antialiasing.

Offline tests cover ordering, queues, input ownership, Source handlers and real
hidden Win32 cursor window, not complete game/performance/visual correctness.
