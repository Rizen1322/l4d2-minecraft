# Changelog

## 2.0.1-alpha.1 — command channel, teammate actions and companion fixes (2026-10-12)

- Replace helper `left4dead2.exe -hijack` processes with an in-process command
  channel: owned `l4d2mc_*` configs run through the add-on via
  `ClientCmd_Unrestricted` on Source's window thread. Plain `ClientCmd` was
  rejected for `exec` (`FCVAR_CLIENTCMD_CAN_EXECUTE`), and a hijack against a
  closed game started a second, Steam-less copy.
- Solo sessions start the local server with `sv_lan 1`, so a flaky Steam
  connection can no longer drop the host ("STEAMAUTH failure code 8 / No Steam
  logon"). Co-op keeps normal authentication.
- Teammate swing/use animations, held-hand/use state and shared burning state;
  host-aim bob pinned per render to remove tick-smoothed hand lag.
- Flint-and-steel on a virtual floor plays its sound and swing; collision
  proxies are explicitly `EF_NODRAW`.
- Four-layer frame export (world, depth, hands, GUI); the compositor accepts
  V1 and V2 frames. Early Source screen-effect pass is opt-in
  (`L4D2MC_EARLY_EFFECTS=1`) until verified in game.
- Companion 2.0.1: guarded update always fetches the latest release, map
  selector/validation, settings normalization, bounded HTTP retries and
  checksum parsing; EXE-first install and friend guides.
- Still pending: full two-PC verification and the in-game check of the early
  screen-effect pass. Third-person Source weapons can still show in F5.

## 2.0.0-alpha.1 — V2 transport, rendering and mobs (2026-10-12)

- Separate latest avatar/mob snapshots from reliable edits and attacks; expire
  stale samples instead of renewing their age on every retransmission.
- Prioritize unassigned combat events while preserving numbered event order;
  replace an old co-op connection only for the same authenticated session.
- Interpolate remote player/entity rendering without changing authoritative
  collision, snap genuine teleports, and stop restarting interpolation on duplicates.
- Capture a wider guest world view without resizing windows; match frame FOV
  metadata and local Steve sampling to reduce reprojection edge gaps.
- Transfer bridged survivor glow to an original six-box Steve silhouette,
  restoring Source glow and removing the proxy when the bridge stops.
- Play shield contact/exhaustion sounds once; use native slash/club damage with
  hit position and impulse for infected reactions.
- Keep validated routes while refreshing, resume at current route progress and
  wait for a route before classifying a mob's target as unreachable.
- Add ground-mob wandering, hostile brain target memories and small-obstacle
  jumping; allow specials/Tanks to pursue registered Minecraft mobs.
- Bound native mob targets to 16 and report the nearest 64 guest mobs. Flying,
  aquatic and boss-specific behavior remains incomplete; see docs/V2.md.


## 0.3.1-alpha.1 — bilingual companion (2026-10-12)

- Switch the companion interface between Russian and English without restarting.
- Persist language selection, translate app messages and keep external tool logs intact.
- Verify translation round trips, dynamic message suffixes and old settings compatibility.

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
