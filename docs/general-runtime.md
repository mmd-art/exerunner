# General Windows runtime

ExeRunner supplies a general Wine environment for Windows applications. Application/game
profiles are optional compatibility overrides; they are not required to add a standalone
program or use the common component manager. Legacy imported game profiles apply to game
entries, so a generic Launcher.exe filename does not assign game overrides to a store client
or ordinary Windows program.

## Components

Open a library card's **… → Windows components…** to view shared libraries for its bottle.
The catalog covers Visual C++, .NET Framework, .NET/Windows Desktop runtimes, DirectX helper
libraries, fonts, MSXML, GDI+ and RichEdit. Available packages are read from the engine's
pinned Winetricks script. Installations are cached and recorded per bottle.

**Settings → Windows applications → Prepare Windows components automatically** enables
static dependency preparation for ordinary standalone programs. The inspector reads
PE32/PE32+ normal and delayed imports plus .NET runtimeconfig metadata. It does not execute
the file during inspection. Adjacent DLLs are respected; native .NET Framework is not
installed merely because an EXE imports mscoree, since Wine Mono supplies that API already.
The latest available v14 package is preferred in a fresh environment; an existing v14
installation is preserved and a newer package is never downgraded by an older recommendation.

Static inspection cannot enumerate DLLs loaded dynamically by program logic. Those failures
remain visible through log diagnostics and the manual component manager. Components are
installed only while the bottle is idle. Installation never silently closes a running app. Cross-process file locks also prevent
another ExeRunner window or shortcut from launching into a bottle during component installation;
other bottles remain available, and the operating system releases the guard after a crash.
A successful component is recorded before the next starts, so failed batches can resume.
Interrupted or failed ExeRunner installations are not accepted merely because upstream logged
a command before its final verification; explicit success records survive app restarts.
Native .NET Framework replaces Wine Mono in the selected bottle; it is an explicit choice.

## Generic application and installer paths

The library accepts standalone EXE files and EXE/MSI installers. An installer starts in its
own directory so adjacent data files remain reachable. MSI reboot-success statuses are
recognized through Wine's Unix exit-code transport. Installer failures are surfaced with a
log path instead of being silently treated as successful setup.

## Repeatable acceptance

```sh
bash tests/runtime-components-test.sh
python3 tests/general-runtime-test.py --engine /path/to/portable/engine
```

The first covers PE bounds/format errors, import inference, runtimeconfig metadata, settings
migration, package validation and partial-install recovery. The second builds self-authored
32/64-bit Win32 controls, a normal MSI payload and WinForms programs, then runs them in a
fresh temporary prefix. It checks Unicode files/registry, DLL exports, GDI font metrics,
MSI installation/launch and Wine Mono WinForms. Only its own prefix is stopped and removed.
Use `--keep` to retain it for inspection. Requires macOS, Rosetta and MinGW-w64.

On 14/10/2026 these controls passed on M2 Pro/macOS 27.2/Wine11.16. Separate shared-installer
checks installed Visual C++2026 and .NET Desktop10 in the test prefix; a managed program ran
on Microsoft.NETCore.App10.0.0. These are standard-runtime tests, not evidence that every
Windows application or every Microsoft servicing revision has been accepted.

Version 0.4 enables CUPS, libusb and OpenCL in the runtime, exposes COM and controller modes,
and selects engines per environment. On 15/10/2026 the general Win32/Win64/MSI/WinForms suite
passed again against that engine. Unicode clipboard transfer passed in both directions, with
the owner's previous clipboard restored. See [device and engine acceptance](devices-and-engines.md)
for printing, serial, MIDI, controller and networking controls and their physical-test boundaries.

Arbitrary Windows kernel drivers, physical COM/MIDI workflows, clean-Mac deployment and
additional machine/OS configurations still need separate acceptance. The universal app binary
has both CPU slices; a Rosetta-hosted x86_64 check is not Intel hardware acceptance.

Format contracts: [Microsoft PE format](https://learn.microsoft.com/en-us/windows/win32/debug/pe-format),
[MSI exit codes](https://learn.microsoft.com/en-us/windows/win32/msi/error-codes).
Package definitions: [Winetricks](https://github.com/Winetricks/winetricks/tree/f3890f670867b5ffbc3938726db45c0f7d16c8ba).
