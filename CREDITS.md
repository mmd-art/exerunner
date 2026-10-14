# Credits and licences

ExeRunner is free software under the GNU General Public License, version 3 or later. See
[LICENSE](LICENSE). It is not affiliated with Apple, Microsoft, Valve or CodeWeavers.

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

## The icon

`app/Resources/AppIcon.png` was generated with ChatGPT's image generation from our sketch (a page
with a wine bottle and "EXE") and cut to Apple's icon grid here. It replaces a first icon that
used an SF Symbol, which Apple's SF Symbols licence does not allow in app icons.

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
- `lib/exerunner/discord-bridge.exe` and `lib/exerunner/audio-test.exe` are built with MinGW-w64
  from `engine/discord-bridge/bridge.c` and `engine/audio-test/audio-test.c` (Whisky's, above).
- **FFmpeg** 7.1.2 (LGPL-2.1-or-later, decoders only, no GPL parts) and GStreamer's **gst-libav**
  1.26.0 (LGPL-2.1-or-later) are built here by `scripts/build-engine.sh media`, from their release
  tarballs, so that game video has decoders.
- The engine inside the app (`scripts/build-engine.sh portable`) also carries libraries wine
  opens and links: FreeType, GnuTLS and what it needs, SDL2, and GStreamer with the plugins
  winegstreamer uses, copied from x86_64 Homebrew by `tools/bundle-libs.py`, with the FFmpeg
  build above, and Homebrew's own FFmpeg, which wine's media module (`winedmo`) links. Their
  formulas, versions and licences are listed in the engine's `LICENSES.md`; most are LGPL or
  permissive, Homebrew's FFmpeg is GPL-3.0-or-later. Sources are at https://formulae.brew.sh and
  with each project.

## D3DMetal

**D3DMetal** belongs to Apple and is not in this repository. Apple's Game Porting Toolkit licence
allows passing it on for non-commercial purposes only, with Apple's notices (sections 2A(iii) and
2C), and allows using it for developing, testing or evaluating games. So:

- builds made by `scripts/build-app.sh` carry the D3DMetal the builder imported from Apple's
  download, with Apple's `License.rtf` and `Acknowledgements.rtf` next to it; ExeRunner is free,
  and must stay free while it carries D3DMetal;
- `scripts/build-app.sh --without-d3dmetal` (or `EXERUNNER_D3DMETAL=0`) builds without it;
- users can always import a newer Game Porting Toolkit in the app; the newer D3DMetal wins.


## DXMT

DXMT 0.80 by Feifan He (3Shain), MIT licence, is bundled as a separate optional
Direct3D 10/11-to-Metal backend. The official release and its published SHA-256 are
pinned in scripts/install-dxmt.sh. Its licence and source/version URL ship
in engine/lib/dxmt. DXMT does not replace Wine's default DLLs or D3DMetal globally.
Source: https://github.com/3Shain/dxmt/tree/v0.80.


## ExeRunner compatibility and general-runtime work

Local, reproducible Wine modifications are stored in `patches/` and applied by
`scripts/build-engine.sh`: native process identity/session integration, DXMT display-mode
emulation, conditional stereo audio downmix, cursor capture and fullscreen presentation.
They extend the upstream Wine implementation; Wine remains LGPL-2.1-or-later.

The execution-breakpoint launcher and adapter in `tools/windows/` are ExeRunner's own
compatibility resources, rebuilt from source during packaging. They implement a scoped
Windows API compatibility path; the application does not distribute game files.

The general Windows-component catalog, read-only PE import inspection, native manager,
installer handling and tests are ExeRunner code. Package installation uses upstream
Winetricks, pinned to revision `f3890f670867b5ffbc3938726db45c0f7d16c8ba` (LGPL-2.1-or-later),
with the script digest checked by the engine build. Its package definitions supply
Microsoft Visual C++, .NET, DirectX libraries and fonts on demand. Microsoft components
retain their own licenses; they are downloaded for the selected bottle rather than added
to ExeRunner's source repository or distributable app.
