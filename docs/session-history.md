# Launch history, playtime and recent applications

Implemented in the isolated `codex/mapc-first-batch` branch on 19/10/2026. No competitor code or dependency was imported.

## Behavior

- History records launch requests, observed sessions, preparation errors, Stop, confirmed crashes and unknown exits. A successful Steam URI helper is not evidence of a successful game exit.
- Only items classified as games receive playtime. Matching uses the existing library/bottle rules, then excludes known launchers, infrastructure, wrapper and crash-reporting executables. Steam client uptime is not charged to a game.
- Process identity includes PID, kernel birth time and a hash of the normalized Windows image plus prefix. Birth time is checked around argument enumeration. A clock captured before enumeration stays with that sample across async suspension; older samples cannot close or reopen newer sessions.
- Elapsed time uses `CLOCK_UPTIME_RAW` and a stable kernel boot-session UUID. Wall-clock changes do not change elapsed time. In-game pauses and background running count; Mac sleep does not. This is observed process runtime, not proof of active human input.
- Sampling is approximately every two seconds. The first observation starts a measured interval; disappearance ends at the last positive checkpoint, without inventing an exit time. Very short processes can have an unmeasured launch entry.
- Stop records intent immediately but does not invent process disappearance. Its status takes precedence over the nonzero result from terminating the process. Known nonzero owned game results and existing crash diagnostics identify crashes; unexplained disappearance remains explicitly unknown. Steam diagnostic windows are reset at the end of each session so old crash text is not reused on a later launch.
- After an observer crashes, the same verified living game can continue its session. If the game ended while no observer was available, only the last checkpoint is retained. A different process or reboot starts another session. A new request reconciles stale open entries before granting outcome ownership.
- GUI and existing headless/shortcut launches use a common actor plus a cross-process file lock and atomic journal writes. Concurrent observers charge each monotonic interval once. Crash evidence addresses an exact session UUID, so a late result cannot relabel a subsequent run.
- Recent applications are deduplicated from positively observed launches, resolved against current library items and limited to ten. They appear in Library and the application menu. No application bundles, LaunchServices registrations or Spotlight duplicates are created.

## Storage and limits

Local metadata only: `~/Library/Application Support/ExeRunner/SessionHistory/history.json` with a regular-file lock. The journal stores item IDs/names, dates, statuses, elapsed seconds and process fingerprints; it does not store launcher arguments, credentials or plaintext game/prefix paths. Local session history is personal usage information; it is not uploaded.

The UI displays 200 entries. Storage retains 2,000 closed sessions, at most 256 open sessions and 10,000 lifetime-total keys, with a 16 MiB file cap. Closed-history pruning preserves lifetime totals. Unsafe paths/symlinks and malformed journals fail closed and leave evidence intact. Unchanged snapshot reads do not rewrite the journal. Process observations persist a small ordering checkpoint, including empty observations, to reject delayed data from other observers. History errors are shown but do not prevent launching an application. Recents use recorded wall-clock dates for presentation and may sort differently after a manual clock correction.

Games, saves, library and settings files, the installed application, selected engine and Mac display settings are not modified by this feature. No backfill of historical Steam time is attempted.

## Validation

`bash scripts/test.sh session-history-test.sh` covers game versus launcher/program time, process appearance, monotonic clock changes, Stop and crash precedence, Steam helper success, unknown exits, observer recovery, PID reuse, reboot, retries after stale owners, delayed scans and delayed crash evidence. Four independent native test processes exercise cross-process journal locking. Additional fixtures cover corrupt data preservation, symlink rejection, bounded history and lifetime-total retention.

`core-test.sh` exercises Wine process enumeration using native synthetic loader processes. `shutdown-test.sh` and `l10n-test.sh` cover existing shutdown coordination and all UI translations. A build-only universal app and `--snapshot-history OUTPUT_DIR` provide a synthetic English UI review without reading owner library/settings or starting games.

Remaining acceptance: actual GUI and existing shortcut launch of a Steam game, Stop and a naturally observed crash in the owner's installed environment. The isolated build is not installed automatically. Arbitrary games spawning an unrecognized persistent helper may need a better generic process classifier; this implementation does not claim universal process attribution or active-input playtime.
