# ExeRunner 0.6.0 alpha

## Add a program that is already installed

Library → Add → **Already installed** (also available from Catalog → Add).
Choose its Windows environment, click **Find EXE**, search by name or Windows path,
select the main program and click **Add**. The same scrolling, grouped chooser is
used after installation; helper EXEs stay under expandable groups. Import only reads
the chosen environment. It does not reinstall the program, create a prefix or change
its engine/settings. A library name may be left blank to use the EXE name.

For Siemens NX 10, first search for `ugraf` in the environment used by its installer.
A synthetic Siemens-style installation tree is covered by the discovery tests; the
recipient's exact installation and successful NX launch have not been verified.

## Updates inside the app

**Settings → Updates → Check for updates…**, or the ExeRunner app menu.
Updates use the pinned Sparkle 2.10 framework, an HTTPS GitHub feed, a signed feed and
EdDSA-signed archives verified before extraction. Automatic background checks/downloads
are off. The user chooses installation in the update dialog; Sparkle replaces only the
app bundle and restarts ExeRunner. Windows programs and operations must finish first;
a new game during download postpones restart. Staged installs also guard termination.

Older versions do not contain the updater: install this DMG once, replacing only the
application in Applications. Existing programs, environments and library remain in
Application Support. Future compatible releases can be installed inside the app.

This alpha is not Developer-ID signed or notarized. EdDSA update verification does not
replace Apple's Gatekeeper trust checks. Initial manual first-open remains necessary;
see INSTALL.md. macOS 15+, Apple Silicon and Rosetta remain required. The runtime is
unchanged: DXMT/DXVK bundled, compatible D3DMetal optional, no experimental D9MT.
No games, saves, personal library, accounts or private signing keys are included.
