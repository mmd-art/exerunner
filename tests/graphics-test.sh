#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/app/Sources/ExeRunner/Core"
WORK="$(mktemp -d /private/tmp/exerunner-graphics-check.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
cp "$ROOT/tests/graphics-test.swift" "$WORK/main.swift"
mkdir -p "$WORK/bin"
ln -s "$ROOT/scripts" "$WORK/scripts"
ln -s "$ROOT/compat" "$WORK/compat"
swiftc -O -module-cache-path "$WORK/modules" -o "$WORK/bin/graphics-test" "$WORK/main.swift" \
 "$SRC/Basics.swift" "$SRC/Settings.swift" "$SRC/VDF.swift" "$SRC/Processes.swift" \
 "$SRC/Diagnostics.swift" "$SRC/Library.swift" "$SRC/Bottles.swift" "$SRC/BottleSettings.swift" \
 "$SRC/Engine.swift" "$SRC/IsolatedWine.swift" "$SRC/PrefixLaunchGate.swift" "$SRC/Recipe.swift" \
 "$SRC/Localization.swift" "$SRC/English.swift" "$SRC/Compat.swift" "$SRC/GraphicsSelection.swift"
EXPECT_WORK="$WORK" "$WORK/bin/graphics-test"
