#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d /private/tmp/exerunner-routing-test.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
# zsh/macOS bash3 both support an ordinary array populated by a glob.
SOURCES=("$ROOT"/app/Sources/ExeRunner/Core/*.swift "$ROOT"/app/Sources/ExeRunner/App/AppState*.swift)
swiftc -O -parse-as-library -module-cache-path "$WORK/modules" "$ROOT/tests/environment-routing-test.swift" "${SOURCES[@]}" -o "$WORK/check"
"$WORK/check" "$WORK"
