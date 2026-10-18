#!/bin/bash
set -euo pipefail
if [ -z "${EXERUNNER_ARTIFACT_SESSION:-}" ]; then
  exec python3 -I "$(cd "$(dirname "$0")/.." && pwd)/tools/artifacts.py" run --label test-session-history -- bash "$0" "$@"
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "$EXERUNNER_WORK_ROOT/history.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
cp "$ROOT/tests/session-history-test.swift" "$WORK/main.swift"
swiftc -O -module-cache-path "$WORK/modules" "$WORK/main.swift" "$ROOT/app/Sources/ExeRunner/Core/SessionHistory.swift" -o "$WORK/check"
"$WORK/check"
