#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp "$ROOT/tests/shutdown-test.swift" "$WORK/main.swift"
SRC="$ROOT/app/Sources/ExeRunner/Core"
swiftc "$WORK/main.swift" "$SRC/PrefixLaunchGate.swift" "$SRC/Basics.swift" "$SRC/Localization.swift" "$SRC/English.swift" -o "$WORK/check"
"$WORK/check"
