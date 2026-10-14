#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/app/Sources/ExeRunner/Core"
WORK="$(mktemp -d /private/tmp/exerunner-runtime-tests.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"
ln -s "$ROOT/scripts" "$WORK/scripts"
ln -s "$ROOT/compat" "$WORK/compat"
swiftc -O -parse-as-library -swift-version 5 -module-cache-path "$WORK/modules" -o "$WORK/bin/check" \
 "$ROOT/tests/runtime-components-test.swift" "$SRC/Basics.swift" "$SRC/Settings.swift" "$SRC/VDF.swift" \
 "$SRC/Processes.swift" "$SRC/Diagnostics.swift" "$SRC/Library.swift" "$SRC/Bottles.swift" "$SRC/BottleSettings.swift" \
 "$SRC/Engine.swift" "$SRC/EngineSelection.swift" "$SRC/IsolatedWine.swift" "$SRC/PrefixLaunchGate.swift" "$SRC/Recipe.swift" \
 "$SRC/Localization.swift" "$SRC/English.swift" "$SRC/Winetricks.swift" "$SRC/PEInspection.swift" "$SRC/RuntimeComponents.swift" "$SRC/WindowsInstaller.swift"
EXPECT_WORK="$WORK" "$WORK/bin/check"
