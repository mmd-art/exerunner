# ExeRunner 0.6.1 — early alpha

## Before installing

- Apple Silicon Mac (including the 14-inch MacBook Pro with M1 Pro).
- **macOS 15 Sequoia or later.** Check Apple menu → About This Mac first. Do not upgrade macOS automatically just for this test.
- Rosetta 2 is required for the bundled Windows compatibility runtime. ExeRunner checks it during setup; any Apple installation prompt is yours to approve.
- About 2 GB for the application, plus space for programs you install. No games, store accounts or saved games are included. Homebrew and Xcode are not required for ordinary use. The optional Game Boost control needs Apple's gamepolicyctl and can remain off.

## Install

1. Download the DMG and compare its SHA-256 with SHA256SUMS.txt from the same release.
2. Open the DMG and drag ExeRunner to Applications. Eject the DMG.
3. Open ExeRunner. This alpha is **not Developer-ID signed or Apple-notarized**. macOS may block the first launch. If you trust the source and verified the file, after trying to open it use System Settings → Privacy & Security → Open Anyway. Approve it yourself. Do not disable Gatekeeper/SIP or run blanket quarantine-removal commands.
4. The first launch should show setup with an empty personal library. Use your own Steam/store account and your own application files. Launcher buttons download software on demand; they are not preinstalled environments.
5. D3DMetal setup is optional: choose Skip to use bundled DXMT (DirectX 10/11) or DXVK/MoltenVK. Import Apple’s toolkit only if that version supports your macOS. The too-new GPTK 4 beta is excluded from this release. DirectX 12 compatibility needs a suitable separate translator.
6. Install one small known application first. Compatibility varies; GTA IV currently has unresolved startup/performance issues.

The interface follows the Mac's language (English/Russian); it can be changed in Settings. The bundled runtime and graphics translators do not require the developer's folders. Windows applications normally access your Mac files/network: use software you trust. Experimental isolation is not a virtual machine.

## Data and uninstall

Your own library, environments and settings are created in ~/Library/Application Support/ExeRunner, with logs/caches in the corresponding Library folders. Removing ExeRunner.app does not delete those programs or saves. Keep backups before removing your own data.

## What has been tested

Release checks include a fresh disposable profile and bundled-runtime controls on the developer's M2 Pro. This is not yet an actual clean M1 Pro/second-Mac acceptance. Please report your macOS version, ExeRunner build, application name and redacted diagnostics if a test fails. No automatic remote support upload is configured.

## Source and licenses

The app is GPL-3.0-or-later. The release includes corresponding application source, build/patch scripts and upstream runtime source information. Third-party components keep their own licenses; Apple D3DMetal is an optional separate import with its own license. Private GitHub hosting does not impose confidentiality on GPL-covered code received by a recipient. See CREDITS.md and the source manifest.

Apple's first-open instructions: https://support.apple.com/en-us/102445
GNU distribution FAQ: https://www.gnu.org/licenses/gpl-faq.en.html#GPLRequireSourcePostedPublic

## Updating and existing programs

Replace only ExeRunner.app in Applications when installing this version. Do not delete
Application Support or rerun Windows installers. Use Add → Already installed → choose
environment → Find EXE to recover a program's library entry. For later releases, use
Settings → Updates → Check for updates… and close Windows programs before installing.
The updater verifies both the feed and update archive; it does not send a hardware profile.
