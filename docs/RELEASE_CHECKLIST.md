# 2.0.11 release checks

Public artifacts: unsigned Windows companion EXE and a source-only ZIP, each with SHA-256. The ZIP embeds SOURCE-MANIFEST.json. No game-derived guest JAR/HUD, game assets, world saves, private configs, credentials or toolchains are uploaded.

- Local Python suite: 151 tests, including real loopback WebSockets, short roster gaps, Source stalls, reconnect/name reassignment, delivery receipts, retained edits, target-facing revive poses, stale-map mailboxes, Windows file contention and combat queue backpressure.
- Fabric/Java build and policy programs; x86 native DLL exports and hidden Win32 cursor/command-window regression.
- 11 Source suites: combat, protection, surfaces, golem/hostile bot targeting, native use/rescue, co-op context, peer combat, projectiles, flight and HUD.
- WPF Release build and companion tests: RU/EN, real Unicode argv, archives, checksums/download retry, local paths and private invitations.
- Runtime smoke on 2.0.10 (native/render code unchanged in 2.0.11): Source/ReShade/Minecraft handshake, shader compilation and full-scene composition. A new by-value ReShade descriptor call caused a test crash; changed to explicit-output D3D9 COM calls and restarted successfully. Full visual correctness is not established by this smoke check.
- Native teammate revive, automatic third-person camera, camera-independent target-facing Steve and the action bar above Steve were confirmed by the author in game. Source progress timer properties were checked on the running map. Tank punch/knockback and hostile Minecraft mob bot targeting have code/handler coverage; extended live and two-PC checks remain pending.

This is a normal GitHub release of the distribution, not a declaration that experimental co-op is complete. See KNOWN_ISSUES.md. CI checks source/Python/companion; owned local game files are required for the full build.
