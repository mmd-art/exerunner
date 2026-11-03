# ExeRunner 0.6.2 alpha

## Clear removal choices

- **Remove entry only…** asks for confirmation and explains that installed files, saves and the Windows environment stay on disk. It does not free disk space. For automatically discovered Steam games it resets saved entry settings; Steam may show the game again.
- **Uninstall game or application…** is a separate action, with access to save backups before continuing. Steam games open Steam's uninstall confirmation; other programs open the Windows environment's installed-program uninstaller. Cancelling or closing the wizard does not automatically remove the library entry.
- Games without an installer can use a native Finder folder selection followed by a second confirmation with the exact path. This moves only the selected dedicated installation directory to the macOS Trash and removes the entry. Saves inside the folder also move to Trash; saves outside stay in place. Back up saves first. Space is freed after the user empties Trash.
- System/profile roots, linked ancestors, folders used by another entry and changed directory identities are rejected. Active or pending launches and teardown block removal. ExeRunner never guesses an installation root from the EXE parent and does not empty Trash automatically.

## Steam Stop diagnostics

Intentional Stop remains intentional across duplicate process-completion callbacks. A fresh launch, including one observed from Steam's UI, starts a new diagnostic session. A missing DLL in Steam's known GPU-query helper is reported as a warning in the Steam-client context instead of a fatal client dependency failure. Real game/main-client dependency failures and nonzero exits remain errors. This does not install or replace Steam DLLs.

## Update

**Settings → Updates → Check for updates…**. Close Windows programs before installing; the signed update restarts ExeRunner. Existing games, accounts and settings are not bundled or replaced.

Apple Silicon, macOS 15+, Rosetta. Same checked runtime as 0.6.1; no experimental D9MT or bundled Apple beta. Ad-hoc signed, not Apple-notarized. Removal of a real application's files by its own uninstaller depends on that application; Wine compatibility is application-specific.
