#!/bin/bash
set -euo pipefail
if [ -z "${EXERUNNER_ARTIFACT_SESSION:-}" ]; then
 exec python3 -I "$(cd "$(dirname "$0")/.." && pwd)/tools/artifacts.py" run --label removal-stop -- bash "$0" "$@"
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$EXERUNNER_WORK_ROOT/removal-check"
mkdir -p "$WORK"
SRC="$ROOT/app/Sources/ExeRunner/Core"
swiftc -module-cache-path "$WORK/modules" "$ROOT/tests/removal-stop-test.swift" "$SRC/StopIntent.swift" "$SRC/GameRemoval.swift" "$SRC/SaveArchive.swift" "$SRC/Diagnostics.swift" -o "$WORK/check"
TEST_COMPAT="$ROOT/compat" "$WORK/check"
