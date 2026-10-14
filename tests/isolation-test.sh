#!/bin/bash
# Real macOS + Windows/Wine probes, including positive controls and descendant inheritance.
# Run outside an existing agent sandbox. Does not execute third-party programs.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE="${1:-/Applications/ExeRunner.app/Contents/Resources/engine}"
WORK="$(mktemp -d /private/tmp/exerunner-isolation-test.XXXXXX)"
cleanup() {
  env -i WINEPREFIX="$WORK/isolated-probe" HOME="$WORK/isolated-probe/.isolation/home" "$ENGINE/bin/wineserver" -k >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT
command -v x86_64-w64-mingw32-gcc >/dev/null
mkdir -p "$WORK/isolated-probe/drive_c" "$WORK/isolated-probe/.isolation/home" "$WORK/isolated-probe/.isolation/tmp"
printf 'offline prototype\n' > "$WORK/isolated-probe/.exerunner-isolated-v1"
cp "$ROOT/tests/isolation-test.swift" "$WORK/main.swift"
SRC="$ROOT/app/Sources/ExeRunner/Core"
swiftc -o "$WORK/harness" "$WORK/main.swift" "$SRC/IsolatedWine.swift" "$SRC/Basics.swift" "$SRC/Engine.swift" "$SRC/EngineSelection.swift" "$SRC/Library.swift" "$SRC/Bottles.swift" "$SRC/Settings.swift" "$SRC/Processes.swift" "$SRC/VDF.swift" "$SRC/Recipe.swift" "$SRC/Localization.swift" "$SRC/English.swift" "$SRC/PrefixLaunchGate.swift"
clang -O2 "$ROOT/tests/isolation-probe.c" -o "$WORK/isolated-probe/native-probe"
x86_64-w64-mingw32-gcc -O2 -static "$ROOT/tests/isolation-probe.c" -lws2_32 -o "$WORK/isolated-probe/drive_c/isolation-probe.exe"
"$WORK/harness" profile "$WORK/isolated-probe" "$ENGINE" "$WORK/profile.sb"
python3 "$ROOT/tests/isolation-test.py" "$WORK" "$ENGINE"
