#!/bin/bash
set -euo pipefail
if [ -z "${EXERUNNER_ARTIFACT_SESSION:-}" ]; then
  exec python3 -I "$(cd "$(dirname "$0")/.." && pwd)/tools/artifacts.py" run --label test-shutdown-test -- bash "$0" "$@"
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp "$ROOT/tests/shutdown-test.swift" "$WORK/main.swift"
SRC="$ROOT/app/Sources/ExeRunner/Core"
swiftc "$WORK/main.swift" "$SRC/PrefixLaunchGate.swift" "$SRC/Basics.swift" "$SRC/Localization.swift" "$SRC/English.swift" -o "$WORK/check"
"$WORK/check"
