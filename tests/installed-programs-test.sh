#!/bin/bash
set -euo pipefail
if [ -z "${EXERUNNER_ARTIFACT_SESSION:-}" ]; then
 exec python3 -I "$(cd "$(dirname "$0")/.." && pwd)/tools/artifacts.py" run --label test-installed-programs -- bash "$0" "$@"
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$EXERUNNER_WORK_ROOT/import-check"
mkdir -p "$WORK"
swiftc -O -module-cache-path "$WORK/modules" "$ROOT/tests/installed-programs-test.swift" "$ROOT/app/Sources/ExeRunner/Core/InstalledPrograms.swift" "$ROOT/app/Sources/ExeRunner/Core/ExecutableDiscovery.swift" -o "$WORK/check"
"$WORK/check" "$WORK/fixture"
