#!/bin/bash
set -euo pipefail
if [ -z "${EXERUNNER_ARTIFACT_SESSION:-}" ]; then
  exec python3 -I "$(cd "$(dirname "$0")/.." && pwd)/tools/artifacts.py" run --label test-launch-modes-test -- bash "$0" "$@"
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/app/Sources/ExeRunner/Core"
WORK="$(mktemp -d "${TMPDIR:-/private/tmp}/exerunner-mode-check.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
cp "$ROOT/tests/launch-modes-test.swift" "$WORK/main.swift"
swiftc -O -module-cache-path "$WORK/module-cache" -o "$WORK/check" "$WORK/main.swift" \
 "$SRC/LaunchModes.swift" "$SRC/IsolatedWine.swift" "$SRC/Basics.swift" "$SRC/Engine.swift" "$SRC/EngineSelection.swift" \
 "$SRC/Library.swift" "$SRC/Bottles.swift" "$SRC/Settings.swift" "$SRC/Processes.swift" "$SRC/VDF.swift" \
 "$SRC/Recipe.swift" "$SRC/Localization.swift" "$SRC/English.swift" "$SRC/PrefixLaunchGate.swift"
mkdir "$WORK/bottles"
"$WORK/check" "$WORK/bottles"
