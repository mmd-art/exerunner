#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp "$ROOT/tests/gamepolicy-fixture.sh" "$WORK/gamepolicy-fixture.sh"
swiftc -swift-version 5 -parse-as-library \
  "$ROOT/tests/game-boost-test.swift" \
  "$ROOT/app/Sources/ExeRunner/Core/GameBoost.swift" \
  "$ROOT/app/Sources/ExeRunner/Core/GameBoostCoordinator.swift" \
  -o "$WORK/check"
"$WORK/check"
