# ExeRunner 0.5.0 alpha

For Apple Silicon Macs running macOS 15 or later. No personal library, games, saves, store sessions or test prefixes are included.

## Changes since 0.4

- Manual save-folder backup and previewed restore, with a verified safety copy before restoration.
- Local launch history, observed-game playtime and recent applications. Launcher uptime is excluded; Stop and observed crash/recovery paths are tracked.
- Optional temporary keep-awake during observed game sessions.
- Dynamic current-display launch arguments and stronger game-process identification behind wrappers.
- Managed build/test artifacts, one checked engine and one rollback instead of accumulating disposable prefixes.
- Refreshed installation notes and distribution checks.

Wine 11.16 and its native dependencies are rebuilt for macOS 15, with DXMT 0.80 and DXVK/MoltenVK included. Apple GPTK 4 beta is omitted: one linked library requires macOS 26.4. D3DMetal can be imported separately if its version supports your macOS. Auto uses available DXMT for eligible DirectX 10/11 applications; known DirectX 9/12 profiles do not select it. **Experimental D9MT is not included.** No claim of a GTA IV fix, arbitrary application compatibility, physical printer/COM/MIDI acceptance or clean M1 Pro validation.

This alpha has no Developer ID/notarization; see INSTALL.md for the manual first-open process. macOS version on the recipient's Mac must be checked first.
