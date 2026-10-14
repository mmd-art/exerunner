# Cursor capture and native display policy

The ExeRunner Wine build confines a finite cursor capture request to the visible owning
window in macOS point coordinates with a two-point inset. A NULL/reset releases; tiny
recenter rectangles and nonintersecting requests are preserved. Game fullscreen capture
also works with multiple outputs. Deactivation releases through the existing Wine path.
The global Settings option is capability-gated by both winemac/win32u markers. Per-item
EXERUNNER_CURSOR_GUARD=0 can opt out; EXERUNNER_CURSOR_TRACE=1 is a capped diagnostic only.

Fullscreen menu/Dock presentation is process-owned, saved/restored on deactivation and
never writes Dock preferences or disables app switching. EXERUNNER_FULLSCREEN_PRESENTATION=0
is the process escape hatch. NativeGameForeground is a one-shot cancelable parent handoff,
using public AppKit activation after a matching visible window exists, respecting deliberate
startup switches. No Accessibility or permanent focus enforcement is needed.

NativeDisplayPolicy reads the selected screen pixel mode/output/refresh. Only known adapters
may rewrite a config. Currently nativeDisplayProfile="farcry-primal" updates the supported
fullscreen XML display fields and backs up the original hash-named bytes under DisplayBackups.
Quality, windowed choices, unknown formats, isolated execution and WoT config are preserved.
Add adapters with byte-preservation, backup/idempotence/concurrency tests and actual native
acceptance; do not claim all games can be rewritten through one unknown config format.

Reproducible source patch: patches/wine-pointer-display.patch, idempotent configure_x86 hook
in scripts/build-engine.sh. Tests: bash tests/cursor-guard-test.sh (ASan/UBSan geometry),
bash tests/native-display-test.sh (supported XML, displays, backups and settings defaults).
The normal app build signs portable components; KEEP_ENGINE_SIGNATURES=1 requires an already
signed verified engine and is not an installation-wide setting.

Accepted on 14/10/2026 at built-in 3456x2234/120Hz: fullscreen menu, camera without hot-corner
lock, Cmd-Tab and mouse release. General unknown configs, multi-monitor native selection and
external4K on this build need separate acceptance. Input/display repair is not measured FPS gain.
