# Display-aware launch arguments

Added19/10/2026. This is an opt-in, app-independent argument-template mechanism, without machine-specific resolutions, user paths or game IDs in the implementation.

Advanced launch arguments may contain `{display.width}`, `{display.height}` and `{display.index}`. Width and height are physical pixels of the selected current mode, not macOS logical points. Index follows Wine's filtered online-display ordering with its primary output first; it is not a GPU adapter ID.

A GUI launch selects the initiating ExeRunner window's screen. A windowless shortcut selects the screen under the pointer. Missing/offscreen window/pointer information falls back to the first available screen; no available physical mode causes an explicit launch error when templates are requested. Screen context is captured before initialization/history/engine awaits and remains fixed through Steam client handoff. Moving the pointer later cannot change an in-progress launch.

Stored library arguments retain the templates. Each launch resolves them into numeric strings only, without a shell. Inline forms such as `--size={display.width}x{display.height}` are supported. Unknown reserved display tokens and unavailable/invalid modes are rejected before preparing a bottle. Arguments without templates retain exact values. Templates are explicitly requested and work independently of the separate automatic profile-adapter setting.

For an app whose documented interface supports these flags, a recipe could use `-fullscreen -width {display.width} -height {display.height}`. ExeRunner does not invent a universal fullscreen command for every program; applications use their own flags or supported profile adapters. Selecting dimensions is not by itself proof that every renderer places its window on a secondary display. Live multi-monitor placement must be accepted separately. Programs launched directly inside a store without ExeRunner's launch path do not automatically receive these templates.

The existing Far Cry profile adapter receives the same captured display rather than sampling again after initialization. No new persistent profile writer or engine patch is added. Mac scaling and display arrangement are only read. Existing explicit manual sizes remain unchanged unless the user edits that app's arguments.

Validation: `bash scripts/test.sh native-display-test.sh` covers physical notebook/external dimensions, profile preservation, repeated launches, invalid templates/missing modes, unchanged stored arguments, inline values, GUI-versus-pointer preference, negative-coordinate screens, disconnected window screens and no-display fallback. These synthetic scenarios establish policy, not physical acceptance on every monitor.
