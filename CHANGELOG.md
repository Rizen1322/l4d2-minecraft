# Changelog

## 2.0.11 — room transport under contention (2026-10-12)

- A correctly framed mailbox from an older map/epoch is discarded instead of disconnecting its sender. Malformed packets remain rejected, and old commands never replace current map state.
- Temporary Windows sharing failures while writing host mailboxes, collision/session manifests, guest pose logs or room status no longer tear down the room. The next fresh snapshot retries the write; log messages are limited to one per ten seconds.
- A full remote-mob combat queue applies reliable backpressure instead of treating its sender as invalid. The blocked hit and following edits stay unacknowledged until capacity is available; camera snapshots continue and accepted damage is not duplicated.
- Added four real loopback socket regressions covering stale-map files, host/guest file contention, ordered combat retries and recovery on the same connection. Versions are 2.0.11 for the companion and guest.
- This reduces specific avoidable disconnect paths; genuine network loss, Source stalls and the remaining render-order limitations are still possible.

## 2.0.10 — co-op recovery and teammate rescue (2026-10-12)

- Short Source roster gaps no longer immediately disconnect a friend. A missing actor has a three-second grace period; a new userid with the same name still reconnects immediately.
- Source camera freshness and room membership now have separate lifetimes. Stale Source data disables controls without revoking a connected guest's membership. Room receive timeout tolerates a short network stall; stale poses remain unusable.
- Hold RMB to use L4D2's native revive/ledge rescue on a downed teammate. An active revive keeps use held inside a 96-unit radius when looking away, with a wall check. Healthy survivors do not intercept item clicks.
- Downed Steve uses the Hunter prone pose. The helper gets a looping, crouched two-handed CPR-style animation, driven by Source's actual revive target, with an automatic temporary third-person camera; the previous F5 mode returns after the revive.
- While helping, Steve faces the rescued teammate independently of the camera. The action bar follows Source's real timer and renders above the avatar in the final GUI layer.
- Survivor bots can target visible hostile Minecraft mobs and deliver bounded owner-side damage. Passive mobs and friendly golems are excluded; native rescue and closer common infected take priority.
- Tank hits request a native attack input pulse and send bounded knockback to the real Minecraft mob. Owned attack input is restored after the pulse and during cleanup.
- Ignore reduced-resolution backbuffer copies when selecting the native screen-effect composition point. This narrows false render checkpoints; complete prop/depth correctness is still not guaranteed.
- Companion and guest versions are 2.0.10. Published as a normal release; co-op gameplay remains experimental, with a fresh two-PC regression still pending.

## 2.0.9-alpha.1 — setup test fix (2026-10-12)

- 2.0.8 treated the Minecraft launcher profile (`versions\L4D2MC-Fabric-26.3\...json`)
  as a replaceable mod file because of its name, so a user-changed profile could be
  overwritten and the installer's own test failed on some PCs. Launcher profiles are
  excluded again; they keep the separate move-aside rule.

## 2.0.8-alpha.1 — updates after playing (2026-10-12)

- Every update after a game session failed with `Installed file was changed
  externally: bin\ReShade.ini`: ReShade rewrites its own ReShade.ini/preset.ini
  while the game runs. The mod's own files are now refreshed even when changed,
  and the changed copy is kept as `*.l4d2mc-previous`. Foreign files are still refused.

## 2.0.7-alpha.1 — teammate outline only when hidden (2026-10-12)

- The Steve-shaped teammate outline used a prop's constant glow, which also draws
  in plain view. It now lights only while no other human survivor can see the
  teammate's body or head (MASK_SOLID traces each tick), like L4D2's own outlines.

## 2.0.6-alpha.1 — mob damage, corpses, AFK, guest JAR (2026-10-12)

- Minecraft mobs could not damage survivors: Source ignores `TakeDamageEx` with a
  null attacker on survivors (verified live). Mob hits now come from `worldspawn`.
- Killed Minecraft mobs stayed lying forever: dead mobs get no Source floor
  support, the void-protection freeze stopped their death tick. Dying mobs now
  finish their death and disappear.
- No more auto-AFK (`director_afk_timeout`, set from the server VM): leaving AFK
  needs +attack, which belongs to Minecraft, so idle players could not return.
- Setup failed with `Build guest jar first`: the guest JAR path was hard-coded to
  2.0.0. It now follows the version in `gradle.properties`.

## 2.0.5-alpha.1 — companion room buttons during a session (2026-10-12)

- Create/copy invitation, join and solo did nothing while the bridge was running:
  every action went through one busy-locked job, and the game session keeps it
  busy. Room actions now run immediately (they only write the local room config),
  show a confirmation, and note that the mode applies at the next bridge start.
  Other actions report why they are unavailable instead of silently doing nothing.

## 2.0.4-alpha.1 — reinstall from a new folder (2026-10-12)

- Installing from the companion's project folder failed with `Existing unowned
  file: ...\bin\ReShade.ini` when the mod had been installed before from another
  folder: the ownership receipt lives in the project. The installer now adopts
  its own previous files (`l4d2mc*` names, `l4d2mc` folders, and a`ReShade.ini`
  whose `AddonPath` is the `l4d2mc` add-on folder) and keeps the old copy as
  `*.l4d2mc-previous`. Foreign loaders such as another `d3d9.dll` are still refused.

## 2.0.3-alpha.1 — no more Steam kick, crash-safe command channel (2026-10-12)

- Host got dropped after a while with "STEAMAUTH failure code 8 / No Steam
  logon": every helper `left4dead2.exe -hijack` initialized Steam and
  invalidated the running game's auth ticket. Commands no longer use `-hijack`.
- The in-process channel now calls the correct engine function. Disassembly of
  retail `engine.dll` (build 10097) through CEngineClient's RTTI vtable showed
  slot 103 is `ExecuteClientCmd` (unrestricted add + execute) and slot 106 is an
  unrelated two-argument vector function, which caused the 2.0.1 crash. The
  add-on checks slot 103's prologue bytes before each call; after a game update
  that moves it, the channel refuses instead of crashing.

## 2.0.2-alpha.1 — L4D2 crash on start fixed (2026-10-12)

- L4D2 closed about a second after the map loaded: retail build 10097 crashed in
  `tier0.dll` (0xC0000417) when the add-on called VEngineClient slot 106 as
  `ClientCmd_Unrestricted` for the first `exec`. Owned configs go through
  Source's `-hijack` forwarding again, started from the running game's own
  executable and only while its window exists, so no second Steam-less copy.

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
