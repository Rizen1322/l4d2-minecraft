# Known issues

- Two-process experiment, Windows/D3D9/x86 host. Local host supported; co-op
  synchronisation, protected sessions and other Workshop/ReShade mods unvalidated.
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
