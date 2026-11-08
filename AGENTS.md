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


## Reader-facing text

Use clean-text for new and edited README prose, product descriptions, interface copy,
help and release notes. Read `.claude/clean-text.md` for this project's readers,
languages, terms and protected claims before writing. Read the installed skill at
`/Users/artemm/.codex/skills/clean-text/SKILL.md`. Its source is
https://github.com/arturtsg-del/clean-text at commit
`669455bbd55ffc4e959e294842588997ee8b5578`. If it is unavailable, report that
the check is incomplete; do not claim to have run it.

Save the original text before editing. Preserve facts, caveats, claim strength,
numbers, units, names, quotations, commands, code and legal wording. Keep the
source language and the existing voice. An expressive slogan may stay when its
meaning is clear. Read the existing personal voice profile if present, but never
create or update it automatically for this project.

Choose the skill's effort level by audience. Run its draft audit, edited-text gate
and draft-versus-edited comparison. Use independent readers as the skill requires,
with only the finished text, reader role and known terms. Select an economical
model and supported low or medium effort explicitly for bounded copy review;
observe the owner's delegation and cost limits. State when independent reading
is unavailable. Resolve fixable findings within the skill's round limits.

On the owner's Mac, every script/check must run through:

```sh
/Users/artemm/lifeos-core/.venv/bin/python /Users/artemm/LifeOS/life/99_System/tools/dev-session/managed_job.py -- python3 /Users/artemm/.codex/skills/clean-text/scripts/audit.py /absolute/path/to/draft.md
/Users/artemm/lifeos-core/.venv/bin/python /Users/artemm/LifeOS/life/99_System/tools/dev-session/managed_job.py -- python3 /Users/artemm/.codex/skills/clean-text/scripts/audit.py /absolute/path/to/edited.md
/Users/artemm/lifeos-core/.venv/bin/python /Users/artemm/LifeOS/life/99_System/tools/dev-session/managed_job.py -- python3 /Users/artemm/.codex/skills/clean-text/scripts/audit.py /absolute/path/to/draft.md --compare /absolute/path/to/edited.md
```

Keep evidence outside disposable scratch and record scratch disposition. Review
what readers see for HTML/PDF/deck changes. Treat code identifiers and visible
strings separately; preserve placeholders and interaction behavior. Deliver
source changes in a separate PR. Merge, deployment, live services, secrets, home
configuration and historical evidence require their own authorization.
