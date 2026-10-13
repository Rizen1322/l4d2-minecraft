# 2.0.12 release checks

Public artifacts: unsigned Windows companion EXE and source-only ZIP, each with SHA-256. The ZIP embeds SOURCE-MANIFEST.json. Game-derived guest JAR/HUD, assets, worlds, private configs, credentials and toolchains are excluded.

- Python suite: 158 tests, including loopback co-op recovery, retained events, stale poses, file contention, performance presets, aspect/bounds and metadata-cache expiry.
- Fabric/Java build and policy programs: collision-cache invalidation, entity load/unload identity, stable nearest selection and the existing gameplay policies.
- x86 native exports and hidden Win32 cursor/command-window regression.
- 11 Source suites, including navigation corner reuse with live geometry traces, combat, rescue, co-op, flight and HUD.
- WPF Release build and companion tests: RU/EN, actual Unicode launcher argv with the performance preset, archive/checksum handling and private invitations. English Play layout inspected.
- Source-only packaging allowlist checked before publication. CI checks Python/source/companion; the full local build requires owned game files.

No games were launched for the 2.0.12 optimization audit or release. ReShade runtime compilation, visual/collision correctness and performance measurements remain pending. Earlier 2.0.10 runtime checks and author-confirmed revive behavior do not validate the new shader or collision changes. A fresh two-PC gameplay check remains pending.

This normal distribution release does not declare experimental co-op complete. See KNOWN_ISSUES.md and PERFORMANCE.md.
