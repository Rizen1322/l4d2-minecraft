# Source alpha release status

- Public target: `Rizen1322/l4d2-minecraft` (origin configured; no push yet).
- Source-only ZIP, SHA256 and embedded manifest; no private HUD/JAR/loader/saves.
- Current README, install/uninstall, known issues, credits, license and bug template.
- Offline CI definition covers Python and source payload checks; GitHub execution
  remains unverified until first push. Full build requires owned local games/tools.
- Native/Fabric/Source build and regressions run locally without games.
- Extracted source ZIP built from scratch with supplied external tool paths:
  own collision model/materials, private HUD, guest, native and all checks passed.
  75 Python tests,13 JVM programs,7 Source suites and Win32 cursor regression.
- Clean-machine install and full in-game regression remain pending. Publish as
  experimental source alpha, not a complete binary release or finished conversion.

Before attaching an artifact, use only the source ZIP and checksum from `release/`.
Generated `dist/` and private guest mods are intentionally excluded. Review the
prepared result before uploading; do not upload your entire workspace folder.
