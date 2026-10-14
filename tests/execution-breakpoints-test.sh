#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d /private/tmp/exerunner-execution-check.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
swiftc -parse-as-library -O -module-cache-path "$WORK/modules" -o "$WORK/check" \
  "$ROOT/tests/execution-breakpoints-test.swift" \
  "$ROOT/app/Sources/ExeRunner/Core/Basics.swift" \
  "$ROOT/app/Sources/ExeRunner/Core/ExecutionBreakpointCompatibility.swift"
"$WORK/check" "$@"
