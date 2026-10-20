#!/bin/bash
set -euo pipefail
if [ -z "${EXERUNNER_ARTIFACT_SESSION:-}" ]; then
 exec python3 -I "$(cd "$(dirname "$0")/.." && pwd)/tools/artifacts.py" run --label test-executable-discovery -- bash "$0" "$@"
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$EXERUNNER_WORK_ROOT/executable-check"
mkdir -p "$WORK"
swiftc -O -module-cache-path "$WORK/modules" "$ROOT/tests/executable-discovery-test.swift" "$ROOT/app/Sources/ExeRunner/Core/ExecutableDiscovery.swift" -o "$WORK/check"
"$WORK/check" "$WORK/fixture"
