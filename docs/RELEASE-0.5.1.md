# ExeRunner 0.5.1 alpha

Fixes the executable chooser after installing a Windows application:

- Search by EXE name or Windows path, including additional/helper executables.
- A bounded scrolling list, grouped under expandable installation folders. Common helper/setup/uninstall files appear under an additional expandable group; files are not removed by the grouping.
- Native Finder EXE selection stays available, with a visible selected path and an explicit Add action. No executable is selected automatically. Missing/non-file selections are rejected before creating a library entry.
- Discovery covers nonstandard C: installation directories and complete per-user AppData folders, excludes Windows system files and does not follow links into Mac folders.
- Existing EXEs remain selectable after a repair/reinstallation, rather than returning only new paths.

The report that prompted this release involved Siemens NX. The overflowing chooser and the discovery limitations were reproduced with synthetic files. The exact missing NX executable/path and successful NX launch on the recipient's Mac are **not yet verified**. This release makes no NX compatibility or licensing claim.

Runtime, graphics components and platform requirements are unchanged from0.5.0: Apple Silicon, macOS15+, Rosetta; bundled DXMT/DXVK, optional compatible D3DMetal import, no experimental D9MT. No games, user library, saves or store sessions included. Not Developer-ID signed/not notarized; see [INSTALL.md](INSTALL.md) for manual first-open instructions.
