# ExeRunner 0.6.3 alpha

## Compact library

Application and game entries now use small icons, inline compatibility labels, a concise running-state/playtime line, file size, and aligned Open/Play and menu controls. Compatibility is separate from whether the application is currently running. Long names wrap without reserving empty title lines.

## File sizes and breakdown

Click an entry's size to see application files and known application caches. Steam's installed games, downloads/user data, Windows environment, ExeRunner/runtime files and other shared data are separate. The library's total button counts the measured scope once, including remaining environments that no longer have a library entry.

Known Steam game folders come from installed manifests, not the Steam executable. Registered installation locations and direct Games/<name> folders can identify other installations. Where ownership is unknown, ExeRunner shows **Size…**, not a fabricated installation size. A native folder picker can select the program folder explicitly; this selection is session-only and does not alter launch settings. Shared-only installations are labelled **Shared files**.

The scanner partitions nested roots and counts each regular file once by filesystem identity (device and inode). Hardlinks shared across categories are assigned to shared files. Automatic scanning does not follow symbolic links, Wine junctions or mapped host drives; external installations can be explicitly selected. Unavailable folders, cooperative time/entry limits and cancellation are handled without blocking the interface; partial results are marked.

These are logical file sizes, **not predicted space reclaimed by uninstalling**. APFS clones have distinct file identities and are not treated as shared hardlinks; clone extents, snapshots, compression and Trash can change actual free-space recovery. Files may change while a scan runs. No cleanup, game launch, component installation or settings change is performed by calculating sizes.

## Update and platform

Settings → Updates → Check for updates. Close Windows programs before installing. Apple Silicon, macOS 15+, Rosetta. Same checked runtime as 0.6.2, no experimental D9MT or bundled Apple beta. Ad-hoc signed, not Apple-notarized.
