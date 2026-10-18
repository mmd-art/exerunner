#!/bin/bash
set -euo pipefail
if [ -z "${EXERUNNER_ARTIFACT_SESSION:-}" ]; then
  exec python3 -I "$(cd "$(dirname "$0")/.." && pwd)/tools/artifacts.py" run --label test-save-archive -- bash "$0" "$@"
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp "$ROOT/tests/save-archive-test.swift" "$WORK/main.swift"
swiftc -O -module-cache-path "$WORK/modules" "$WORK/main.swift" \
 "$ROOT/app/Sources/ExeRunner/Core/SaveArchive.swift" \
 "$ROOT/app/Sources/ExeRunner/Core/SaveOperationTracker.swift" \
 "$ROOT/app/Sources/ExeRunner/Core/KeepAwake.swift" -o "$WORK/check"
"$WORK/check" "$@"
