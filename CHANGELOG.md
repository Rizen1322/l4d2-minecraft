# Changelog

## 0.3.0-alpha.1 — desktop companion and combat audio (2026-10-12)

- Add a small Windows desktop EXE with game autodetection, verified source
  downloads, private tool preparation, installation, co-op invitations and launch.
- Preserve host room tokens across invitation copies; joining uses the player's
  own L4D2 nickname. Keep invitation secrets out of process arguments and logs.
- Validate archive paths and release manifests before copying source files.
- Play vanilla Minecraft weak/strong/sweep sounds for confirmed Source hits,
  with a sword swing sound and retry deduplication. Ignore dead combat targets.
- Exercise the embedded Python setup, tool downloads and clean source build.
  Actual game audio and a full two-PC GUI install still need user verification.


## 0.2.0-alpha.1 — co-op transport and remote combat (2026-10-11)

- Keep block edits through congestion and reconnect; session IDs deduplicate
  accepted events so old edits cannot overwrite newer room state.
- Acknowledge room commands after Minecraft server dispatch, with bounded
  delivery windows, retries and protection against stale/out-of-order receipts.
- Separate network membership leases from the frozen-Source watchdog; compensate
  tick pacing for round-trip time and retry malformed/stale room responses.
- Route melee against remote Minecraft mobs to their owning guest server with
  scene, distance, ownership and duplicate-damage checks.
- Drain guest event bursts in batches. Coalesced Source reply acknowledgements
  no longer evict attacks from the gameplay event queue.
- Retain projectile launch origins and trace the first flight segment immediately.
  Synchronize aim before item use and remove front-camera physical pitch reversal.
- Repair portable setup: preserve Zig standard-library directories, use a
  verified 32-bit Squirrel checker, capture process exit codes, preserve existing
  Minecraft profiles, and fix PowerShell launcher argument quoting.
- Add `Coop.bat`, `Update-Coop.cmd`, connection/roster diagnostics, deployment
  documentation and a source-only release containing the co-op entry points.

The previous LAN/Elytra work below is included in this release. Offline
verification does not establish complete two-PC gameplay correctness.

## Unreleased — experimental LAN and Elytra (2026-10-10)

- Per-survivor Source gameplay/survival/navigation contexts and validated
  authenticated LAN mailboxes; room name pairing resolves changed Source userids.
- Shared bounded block-state edits, deletion history and reconnect snapshots;
  client-only Steve/mob/TNT/projectile visuals. No shared container NBT.
- Equipped Elytra flight/rocket physics changes native Source velocity, keeps
  collisions and restores gravity after ground/menu/pins/lease expiration.
- Shift visually crouches Steve; actual eating/drinking temporarily slows native
  movement, preserving original speed and potion multipliers on restoration.
- Hide owned attached weapon world models in third person; restore visibility
  when dropped. Native wheel works for joiners, with menu/focus ownership guards.
- Extend loopback, guest policy, native window and real Source-handler tests.

The room is intended for a private LAN. A complete two-PC test is pending.

## Unreleased — alpha source preparation (2026-10-09)

- Additional agent audit: correct current temporary-HP decay during healing and
  golden apples; recover stalled/external window resizes without immediate repeats.
- Preserve new collision regions when cache is full; expire stalled guest mob,
  projectile and physics snapshots; retry replies after integrated-server replacement.
- Preflight the whole update before writes; stage/hash/replace each file, recheck
  concurrent user edits, persist a recovery journal and roll back receipt IO failure.

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
