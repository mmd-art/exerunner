#!/bin/bash
set -euo pipefail
if [ -z "${EXERUNNER_ARTIFACT_SESSION:-}" ]; then
 exec python3 -I "$(cd "$(dirname "$0")/.." && pwd)/tools/artifacts.py" run --label storage-test -- bash "$0" "$@"
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$EXERUNNER_WORK_ROOT/storage-test"; mkdir -p "$WORK"
SRC="$ROOT/app/Sources/ExeRunner/Core"
swiftc -module-cache-path "$WORK/modules" "$SRC/StorageScan.swift" "$SRC/StorageSources.swift" "$ROOT/tests/storage-test.swift" -o "$WORK/check"
"$WORK/check"
