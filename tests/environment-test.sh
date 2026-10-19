#!/bin/bash
set -euo pipefail
if [ -z "${EXERUNNER_ARTIFACT_SESSION:-}" ]; then
  exec python3 -I "$(cd "$(dirname "$0")/.." && pwd)/tools/artifacts.py" run --label test-environment-test -- bash "$0" "$@"
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/app/Sources/ExeRunner/Core"
WORK="$(mktemp -d "${TMPDIR:-/private/tmp}/exerunner-environment-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
cp "$ROOT/tests/environment-test.swift" "$WORK/main.swift"
swiftc -O -module-cache-path "$WORK/modules" -o "$WORK/check" "$WORK/main.swift" \
 "$SRC/Basics.swift" "$SRC/Settings.swift" "$SRC/VDF.swift" "$SRC/Processes.swift" "$SRC/Diagnostics.swift" \
 "$SRC/Library.swift" "$SRC/Bottles.swift" "$SRC/BottleSettings.swift" "$SRC/Engine.swift" "$SRC/EngineSelection.swift" \
 "$SRC/SerialPorts.swift" "$SRC/ControllerMapping.swift" "$SRC/IsolatedWine.swift" "$SRC/PrefixLaunchGate.swift" "$SRC/Recipe.swift" "$SRC/Localization.swift" "$SRC/English.swift"
EXPECT_WORK="$WORK" "$WORK/check"
