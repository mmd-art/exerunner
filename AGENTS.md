# ExeRunner development artifacts

Keep games, saves, owner settings, installed /Applications/ExeRunner.app and authored source intact.
Use script/build_and_run.sh --build-only for UI checks without quitting games. Install only through
scripts/install-app.sh; it refuses a busy app/runtime and retains one previous verified app.
Never create timestamped app/engine backups or test prefixes in LifeOS/logs, /Applications or /tmp.
Use tools/artifacts.py run --label NAME -- COMMAND for one-off builds, probes and profiling; put
outputs under EXERUNNER_WORK_ROOT or TMPDIR. Export small reports/source/media before the session ends.
Use scripts/test.sh TEST.sh or TEST.py; direct committed test entrypoints also use the managed runner.
A complete scripts/build-engine.sh all uses disposable build/compiler caches. Individual tools,
configure/make stages are an explicitly incremental development work tree, not archival copies.
Promote an engine only with scripts/verify-engine.sh PATH (native controls must pass); do not mutate
or replace the currently pinned engine in place. build-devices-engine.sh does this automatically.
Use scripts/make-dmg.sh for a single current installer. tools/artifacts.py gc removes only marked,
inactive managed sessions; unknown files and changed/active retained artifacts are never swept.
Keep one rollback and one checked engine; tools/artifacts.py status shows their actual paths.
Do not bypass this policy with broad find/rm, cp/ditto backups or unbounded --keep evidence flags.
