#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="${1:?output executable path}"
CACHE="$(mktemp -d /private/tmp/exerunner-mapper-compile.XXXXXX)"
trap 'rm -rf "$CACHE"' EXIT
SOURCES=("$ROOT"/app/Sources/ExeRunner/Core/*.swift "$ROOT"/app/Sources/ExeRunner/App/AppState*.swift)
swiftc -O -parse-as-library -module-cache-path "$CACHE/modules" "$ROOT/tests/environment-native-helper.swift" "${SOURCES[@]}" -o "$OUTPUT"
