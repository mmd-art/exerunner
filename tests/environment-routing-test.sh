#!/bin/bash
set -euo pipefail
if [ -z "${EXERUNNER_ARTIFACT_SESSION:-}" ]; then
  exec python3 -I "$(cd "$(dirname "$0")/.." && pwd)/tools/artifacts.py" run --label test-environment-routing-test -- bash "$0" "$@"
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/private/tmp}/exerunner-routing-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
# zsh/macOS bash3 both support an ordinary array populated by a glob.
SOURCES=("$ROOT"/app/Sources/ExeRunner/Core/*.swift "$ROOT"/app/Sources/ExeRunner/App/AppState*.swift)
swiftc -O -parse-as-library -module-cache-path "$WORK/modules" "$ROOT/tests/environment-routing-test.swift" "${SOURCES[@]}" -o "$WORK/check"
"$WORK/check" "$WORK"
