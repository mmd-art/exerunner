#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d /private/tmp/exerunner-cursor-guard.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
clang -g -fsanitize=address,undefined -I"$ROOT/engine/src/dlls/winemac.drv" \
 "$ROOT/tests/cursor-guard-test.c" -framework CoreGraphics -o "$WORK/check"
"$WORK/check"
