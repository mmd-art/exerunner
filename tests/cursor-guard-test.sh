#!/bin/bash
set -euo pipefail
if [ -z "${EXERUNNER_ARTIFACT_SESSION:-}" ]; then
  exec python3 -I "$(cd "$(dirname "$0")/.." && pwd)/tools/artifacts.py" run --label test-cursor-guard-test -- bash "$0" "$@"
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/private/tmp}/exerunner-cursor-guard.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
clang -g -fsanitize=address,undefined -I"$ROOT/engine/src/dlls/winemac.drv" \
 "$ROOT/tests/cursor-guard-test.c" -framework CoreGraphics -o "$WORK/check"
"$WORK/check"
