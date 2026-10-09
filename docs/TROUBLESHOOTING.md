# Troubleshooting and uninstall

Missing overlay: confirm guest profile/bridge and Minecraft rendering. Check
L4D2 `bin/ReShade.log` for FX/add-on errors. Transport alone does not prove shader
compiled. Source/guest scene tokens must match; stale frames are hidden.

Locked update: exit L4D2 normally and rerun launcher (runs update.py first).
Do not delete/rename a loaded DLL. Cursor hook pins its code until exit; hot unload
unsupported. Use matching guest/native versions and avoid duplicate bridges.

Bug reports: map/versions/action sequence, brief sanitized launcher/bridge log,
Minecraft launcher `logs/latest.log` or guest `crash-reports/`, `bin/ReShade.log`.
Never upload launcher command lines, access tokens, whole profiles or saves.

Removal: close games/bridge, run `python passthrough/install.py uninstall` from
same checkout. Only unchanged owned files are removed; modified/unowned files
and guest worlds remain. Preserve `backups/` receipt and launch addon/control
recovery files if console was killed. Never delete an unrelated d3d9.dll.

Interrupted updates: preserve `backups/passthrough-install.json` and its `.pending`
journal. The next update reconciles completed replacements by old/new checksums.
If it reports an external change, leave those files intact and review that change;
the updater refuses to overwrite it. Do not run multiple installers concurrently.
