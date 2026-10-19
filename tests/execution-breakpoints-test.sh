#!/bin/bash
set -euo pipefail
if [ -z "${EXERUNNER_ARTIFACT_SESSION:-}" ]; then
  exec python3 -I "$(cd "$(dirname "$0")/.." && pwd)/tools/artifacts.py" run --label test-execution-breakpoints-test -- bash "$0" "$@"
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/private/tmp}/exerunner-execution-check.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
swiftc -parse-as-library -O -module-cache-path "$WORK/modules" -o "$WORK/check" \
  "$ROOT/tests/execution-breakpoints-test.swift" \
  "$ROOT/app/Sources/ExeRunner/Core/Basics.swift" \
  "$ROOT/app/Sources/ExeRunner/Core/ExecutionBreakpointCompatibility.swift"
"$WORK/check" "$@"
