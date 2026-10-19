#!/bin/bash
set -euo pipefail
if [ -z "${EXERUNNER_ARTIFACT_SESSION:-}" ]; then
  exec python3 -I "$(cd "$(dirname "$0")/.." && pwd)/tools/artifacts.py" run --label test-game-boost-test -- bash "$0" "$@"
fi
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
