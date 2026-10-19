#!/bin/bash
set -euo pipefail
if [ -z "${EXERUNNER_ARTIFACT_SESSION:-}" ]; then
  exec python3 -I "$(cd "$(dirname "$0")/.." && pwd)/tools/artifacts.py" run --label test-environment-native-helper -- bash "$0" "$@"
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="${1:?output executable path}"
CACHE="$(mktemp -d "${TMPDIR:-/private/tmp}/exerunner-mapper-compile.XXXXXX")"
trap 'rm -rf "$CACHE"' EXIT
SOURCES=("$ROOT"/app/Sources/ExeRunner/Core/*.swift "$ROOT"/app/Sources/ExeRunner/App/AppState*.swift)
swiftc -O -parse-as-library -module-cache-path "$CACHE/modules" "$ROOT/tests/environment-native-helper.swift" "${SOURCES[@]}" -o "$OUTPUT"
