# Windows environments, engines and devices

ExeRunner 0.4 keeps the general platform configuration separate from application profiles.
Every library card exposes **Windows environment, engine and devices…**; all entries in that
bottle share the selected engine and device policy. No list of named programs is needed.

## Engines

`BottleSettings.enginePath` is optional: older records inherit the application default.
An explicit choice must contain executable `bin/wine` and `bin/wineserver`; an unavailable
choice is a visible error. Installation, launch, runtime-component setup, diagnostics,
DLL paths, audio tests and Stop resolve the same engine. Process tracking includes renamed
Wine/CEF loader copies from every configured engine. Changing a busy environment or a busy
inherited default is refused. The picker selects existing engines; it does not download or
certify arbitrary third-party builds.

Plain external Wine can launch an ordinary program without DXVK. A launcher recipe or an
explicit DXVK/DXMT/vkd3d choice still requires its corresponding libraries. Apple's D3DMetal
is available only on Apple Silicon and with an engine containing ExeRunner's compatible
loading module. It is not advertised just because a global Apple download is present.

The app executable is universal (arm64 and x86_64, minimum macOS 15). On Intel, onboarding
skips Rosetta and D3DMetal and labels support experimental. Both slices can be built locally;
Intel hardware and another macOS version remain external acceptance items.

## Printing and serial ports

Wine exposes configured CUPS printers to Windows applications. Printing stays in the
application's own Print dialog. The panel's printer-settings action starts `control printers`
in the selected environment without preparing game graphics or changing Mac display settings.

COM1–COM255 can map to native character devices under `/dev`. USB serial adapters need their
Mac driver first. The UI avoids COM numbers configured outside ExeRunner, retains disconnected
saved mappings and refuses regular files, invalid paths and duplicate numbers. The ownership
record and registry changes affect only ExeRunner's mappings. Serial preparation holds the
same exclusive prefix lease as component installation; another program cannot enter midway.
The registry is imported as UTF-16LE so Unicode paths and settings remain intact.

Wine's mount manager reads the old registry when the import helper starts. Preparation
therefore flushes/stops only the idle environment's helpers before reconciling its symlinks;
this prevents an explicitly removed COM link from reappearing.

## Controllers, USB, MIDI and networking

**Automatic** leaves Wine's existing controller policy alone. **Xbox / XInput** enables SDL
mapping of compatible gamepads; **Native HID** keeps raw device input. Before an explicit
change, ExeRunner records the original WineBus values. Automatic restores that snapshot.
Only three owned policy values are changed. External edits or an invalid ownership record
produce an error; they are not silently overwritten. A pending record retains the original
policy through an interrupted update. Switching requires an idle environment and applies
on the next launch. Native and mapped interfaces expose different controller features;
rumble, adaptive triggers and every controller model are not asserted by the input controls.

The panel inventories Mac USB/HID/MIDI devices without opening or seizing them. Engine
capabilities are checked from installed bridge modules. USB presence alone does not mean a
Windows-specific driver or protocol works. USB Ethernet uses the Mac network stack rather
than a Windows kernel driver; USB serial normally uses a Mac serial driver and COM mapping.
CoreMIDI supplies Windows WinMM MIDI endpoints. ASIO, FTDI D2XX and arbitrary Windows kernel
drivers are outside the implemented standard-device layer.

Windows sockets use macOS networking. The network control exercises UDP and TCP against
private native loopback servers, including byte-preservation of Art-Net/sACN/OSC-shaped
payloads. It does not transmit to a lighting desk or demonstrate complete hardware protocols.

## Experimental DX12 fallback

The explicit **vkd3d (DX12 · Vulkan)** renderer uses Wine's bundled vkd3d and MoltenVK,
with per-executable built-in D3D12/DXGI overrides. It does not replace existing Auto/game
choices or enable vkd3d-proton. On the M2 Pro control it creates a device at feature level
11_0, shader model 6.0, binding tier 1 and no ray tracing. A GPU texture clear, copy, fence
and 256-pixel readback passed. This is limited DX12 API acceptance, not acceptance of modern
DX12 games. The isolated prototype does not expose this unvalidated renderer path.

## Repeatable controls and recorded evidence

```sh
bash tests/environment-test.sh
bash tests/environment-routing-test.sh
python3 tests/devices-test.py --engine /path/to/portable/engine
python3 tests/clipboard-test.py --engine /path/to/portable/engine
python3 tests/network-test.py --engine /path/to/portable/engine
python3 tests/controller-test.py --engine /path/to/portable/engine --mode xinput --seconds 30
```

These tests use their own prefixes and self-authored Windows fixtures, without an account
or a particular application. The device suite uses print-to-file, a pseudo-terminal and a
virtual CoreMIDI destination; it sends no paper job or physical MIDI/serial commands. The
clipboard helper retains every previous pasteboard representation in memory and restores
it unless the owner copied something else during the check. Nothing copied is printed or
saved to the test log. The controller sampler only reads states and does not request rumble.

Recorded on M2 Pro/macOS 27.2/Wine 11.16, 15/10/2026:

| Control | Result | Boundary |
| --- | --- | --- |
| CUPS / GDI printing | Three Mac printers discovered; PostScript generated; physical queue unchanged | Paper output not sent |
| App serial preparation | COM22 setup/removal, baud/state, bidirectional PTY and manual COM23 preservation | Physical USB serial not connected |
| MIDI | WinMM message received by native virtual CoreMIDI endpoint | Physical MIDI interface not connected |
| USB/HID/OpenCL APIs | API inventory passed; OpenCL platform returned | No WinUSB transfer device/protocol tested |
| Clipboard | Unicode in both directions; previous content restored | Test-owned text only |
| Networking | Windows adapter inventory, UDP/TCP native-loopback exchange passed | External desk/device operation not tested |
| Bluetooth DualSense | Native WinMM and mapped XInput enumeration; button/stick sampler | Other models and force feedback pending |
| Engine routing | Default/custom engines reached the actual launcher with matching DLL roots | Two controlled engine fixtures |
| Existing runtime | Win32/Win64/MSI/WinForms suite passed against device-enabled engine | No universal application guarantee |

Physical printer, COM and MIDI acceptance, clean installation on a second Mac, Intel
hardware and display transitions remain to be tested. Known-good game settings and Mac
scaling are not changed by these controls.
