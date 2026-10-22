#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -z "${EXERUNNER_ARTIFACT_SESSION:-}" ]; then
 exec python3 -I "$ROOT/tools/artifacts.py" run --label test-installed-shortcuts -- bash "$0" "$@"
fi
WORK="$EXERUNNER_WORK_ROOT/shortcuts-check"
mkdir -p "$WORK"
swiftc -O -module-cache-path "$WORK/modules" "$ROOT/tests/installed-shortcuts-test.swift" "$ROOT/app/Sources/ExeRunner/Core/ExecutableDiscovery.swift" "$ROOT/app/Sources/ExeRunner/Core/ExecutableTree.swift" "$ROOT/app/Sources/ExeRunner/Core/InstalledShortcut.swift" -o "$WORK/check"
"$WORK/check" "$WORK/fixture"
