# Installed-program chooser

The chooser reads existing C: content and does not run shortcuts or installers to identify applications.

- Detected applications uses friendly names from direct EXE shortcuts in public/user Start Menu Programs and Desktop folders. Copies with the same name and target are deduplicated. Selecting a shortcut suggests its name when the user has not supplied a custom library name.
- All EXEs preserves every nested directory; opening a vendor does not flatten all its executables. Common helper/install/update/crash EXEs remain accessible in an Additional EXEs group within their actual folder.
- Wine's Internet Explorer, Windows Media Player and Windows NT folders are in a separate initially collapsed system-utilities section. Java and other installed applications are not classified as system utilities by name similarity.
- Search matches friendly shortcut names and full Windows paths; matching folders expand to expose results. The list scrolls inside a fixed viewport, and manual selection uses the existing native Finder NSOpenPanel.
- Installation status uses the same leading edge as the title, a wrapping status label and an indeterminate horizontal progress indicator. The indicator does not represent a measured installation percentage.

## Shortcut limits

This initial read-only parser supports MS-SHLLINK local LinkInfo paths (ANSI/UTF-16) and StringData relative paths, matching only the already-discovered EXE allowlist in the selected C: drive. It validates structure bounds and header identity, ignores symlinks and limits each shortcut to 1 MiB. No COM, shell-link execution, UNC or non-C drive access is used.

Shortcuts needing arguments, a distinct working directory, environment expansion, shell-ID-list-only resolution or other unsupported metadata are omitted from Detected applications rather than silently losing launch semantics. Their EXEs remain available in All EXEs and the native manual picker. No uninstall-registry guessing or vendor-specific main-EXE ranking is performed. Siemens NX and its licensing/runtime compatibility remain separate, unverified concerns.

Format reference: [Microsoft MS-SHLLINK LinkInfo](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-shllink/6813269d-0cc8-4be2-933f-e96e8e3412dc).

## Verification

Run `bash tests/installed-shortcuts-test.sh`, the existing executable discovery/import/native picker tests, and `bash tests/l10n-test.sh` through the project's managed artifact runner. `--snapshot-executable-choice` renders synthetic application names, a nested NX-like directory tree with hundreds of EXEs, search/no-match views and long EN/RU installation statuses without running NX.
