# Changelog

## Unreleased — alpha source preparation (2026-10-09)

- Retry congestion-blocked totem confirmations and completed mob routes without
  duplicating queued responses; discard old-round navigation jobs.
- Restore held input after reconnect; immediately release GUI/native ownership
  on disconnect. Coalesce Source snapshots instead of growing server work.
- Reject stale controller/scene inputs and world clicks delivered behind inventory.
- Portable paths, parameterised build tools, explicit setup script, current docs
  and reproducible source ZIP with checksums.
- Clean source install generates required native collision cube/materials;
  ReShade x86/API preflight rejects wrong loaders before installing.
- Offline CI and bug report template; no private game-derived CI artifacts.
- Prior cursor fix handles resets on the window thread and yields Source/ReShade
  menus; prior fall-totem repair checks safe landing and confirms after physics.

Offline verification does not replace clean-machine installation/in-game testing.
No claim of complete Minecraft compatibility or production stability.
