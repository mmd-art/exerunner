#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/app/Sources/ExeRunner/Core"
WORK="$(mktemp -d /private/tmp/exerunner-mode-check.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
cp "$ROOT/tests/launch-modes-test.swift" "$WORK/main.swift"
swiftc -O -module-cache-path "$WORK/module-cache" -o "$WORK/check" "$WORK/main.swift" \
 "$SRC/LaunchModes.swift" "$SRC/IsolatedWine.swift" "$SRC/Basics.swift" "$SRC/Engine.swift" \
 "$SRC/Library.swift" "$SRC/Bottles.swift" "$SRC/Settings.swift" "$SRC/Processes.swift" "$SRC/VDF.swift" \
 "$SRC/Recipe.swift" "$SRC/Localization.swift" "$SRC/English.swift" "$SRC/PrefixLaunchGate.swift"
mkdir "$WORK/bottles"
"$WORK/check" "$WORK/bottles"
