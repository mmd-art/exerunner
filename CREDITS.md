# Credits and licences

WinRunner (working name) is free software under the GNU General Public License, version 3 or
later. See [LICENSE](LICENSE).

## Taken from other projects

- **Whisky**, by Isaac Marovitz and contributors, and its maintained fork **frankea/Whisky**
  (GPL-3.0-or-later), commit `3abfbae`:
  - `compat/games.json` is converted from its game compatibility database
    (`WhiskyKit/Sources/WhiskyKit/GameDatabase/Resources/GameDB.json`) by
    `tools/import-whisky-gamedb.py`;
  - launcher fixes in `recipes/*.recipe` (environment variables, which helper processes draw
    through DXVK, NVIDIA's libraries off in Chromium helpers, the Rockstar launcher's d3d12) come
    from `WhiskyKit/Sources/WhiskyKit/Wine/LauncherPresets.swift`, `Steam/SteamLauncher.swift`
    and the fork's Steam compatibility guide; telling launchers apart by file name and path
    (`Core/Launchers.swift`) and the Rockstar titles on Steam from `LauncherDetector.swift` and
    `LaunchResolver.swift`;
  - `compat/crash-patterns.json` is converted from `Diagnostics/Resources/patterns.json` by
    `tools/import-whisky-crash-patterns.py`; the log window the classifier reads, the redaction
    rules and what a diagnostic report contains follow `CrashClassifier.swift`,
    `Wine/Wine.swift`, `Redactor.swift` and `DiagnosticExporter.swift`;
  - the log level presets (`WineDebugPreset.swift`), the check that a bottle is complete
    (`WinePrefixValidation.swift`), the eight problem areas of the helper
    (`Troubleshooting/Resources/index.json`) and the audio device thresholds
    (`Audio/CoreAudioDeviceProbe.swift`);
  - the audio driver and DirectSound buffer values (`WineAudioRegistry.swift`,
    `BottleAudioConfig.swift`), the CJK font aliases (`WineFontReplacements.swift`) and the
    fonts copied into bottles (`BottleFontBootstrap.swift`);
  - `engine/discord-bridge/bridge.c` is `scripts/discord-bridge/bridge.c`, renamed only.
- **frankea/winecx-gptk**: the engine source tree it builds from (below) and the build lessons
  noted in `scripts/build-engine.sh` (gcc for the Windows half, Wine tools built native).

## The engine

Built by `scripts/build-engine.sh`; nothing below is modified here unless said so.

- **Wine** (LGPL-2.1-or-later), with **CodeWeavers' CrossOver 26.3** changes (LGPL), as carried by
  `dappermint/winecx` on Wine 11.16. Checked against the official Wine and CrossOver sources.
- **lsteamclient** from **Valve's Proton** (LGPL-2.1), inside that tree.
- **FAudio** (zlib), inside that tree.
- **DXVK** for macOS by Gcenx and Philip Rebohle (zlib).
- **MoltenVK** by the Khronos Group (Apache-2.0).
- **Wine Mono** and **Wine Gecko** (their own open licences), downloaded from WineHQ.
- **winetricks** (LGPL-2.1-or-later).
- `engine/compat/cxcompatdb.c` is ours. It implements the module name and the two functions
  CrossOver's Wine exports for it (`prepend_dll_path`, `add_load_order_override`); CrossOver's
  own module is closed and is not used.
- `lib/winrunner/discord-bridge.exe` is built with MinGW-w64 from `engine/discord-bridge/bridge.c`
  (Whisky's, above).
- The engine inside the app (`scripts/build-engine.sh portable`) also carries libraries wine
  opens and links: FreeType, GnuTLS and what it needs, SDL2, GStreamer with a set of plugins, and
  FFmpeg, copied from x86_64 Homebrew by `tools/bundle-libs.py`. Their formulas, versions and
  licences are listed in the engine's `LICENSES.md`; most are LGPL or permissive, FFmpeg as
  Homebrew builds it is GPL-3.0-or-later. Sources are at https://formulae.brew.sh and with each
  project.

## Not included

**D3DMetal** belongs to Apple and its licence does not allow redistribution. Every user
downloads Game Porting Toolkit from developer.apple.com with their own Apple ID and imports it
into the app.
