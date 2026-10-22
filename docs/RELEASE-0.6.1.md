# ExeRunner 0.6.1 alpha

## Easier installed-program selection

- Detected applications shows names from supported Start Menu/Desktop shortcuts, so the main EXE need not be remembered.
- All EXEs preserves nested installation folders. Opening a vendor no longer flattens hundreds of executables.
- Common helper EXEs stay in a separate group in their actual folder; Wine system utilities are separated from installed applications.
- Search matches application names and full paths. Scrolling stays inside the chooser and native Finder manual selection remains available.
- Installation status shares the title's leading edge and wraps long text.

The dynamic chooser now uses a lazy scrolling view instead of a table-backed SwiftUI List. This avoids the reproduced NSTableView delegate reentrancy warning during expansion/search on macOS 27.

## Update from 0.6.0

Open **Settings → Updates → Check for updates…**. Close Windows programs before installing; ExeRunner restarts after the signed update is installed. No NX reinstall is needed. Earlier releases without the updater need one manual DMG installation.

## Limits

Shortcut suggestions currently support direct EXE links. Shortcuts requiring arguments, a distinct working directory, environment expansion or shell-ID-list-only resolution are not suggested automatically; their EXEs remain available in the tree/manual picker. This release does not establish Siemens NX or license-server compatibility.

Apple Silicon, macOS 15+, Rosetta. The checked runtime is unchanged; no experimental D9MT or personal data is bundled. Ad-hoc signed, not Apple-notarized. Sparkle payload/feed signatures do not replace Gatekeeper notarization.
