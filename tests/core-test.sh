#!/bin/bash
# Builds tests/core-test.swift with the app's parsing code and runs it, with two fake wine
# processes in the process table (named wine, arguments shifted in place as wine's rebuild_argv
# does) so that reading them back is tested too.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/app/Sources/ExeRunner/Core"
WORK="$(mktemp -d)"
FAKES=()
trap 'kill "${FAKES[@]}" 2>/dev/null || true; rm -rf "$WORK"' EXIT

cat > "$WORK/wine.c" <<'C'
#include <string.h>
#include <unistd.h>
int main(int argc, char **argv)
{
    int offset = argv[1] - argv[0];
    char *end = argv[argc - 1] + strlen(argv[argc - 1]) + 1;
    memmove(argv[0], argv[1], end - argv[1]);
    memset(end - offset, 0, offset);
#ifdef IMPOSTOR
    sleep(61);
#else
    sleep(60);
#endif
    return 0;
}
C
clang -O0 -o "$WORK/wine" "$WORK/wine.c"
mkdir -p "$WORK/bottles/steam" "$WORK/winetemp-copy" "$WORK/winetemp-other" "$WORK/ordinary-copy"
cp "$WORK/wine" "$WORK/winetemp-copy/cef_subprocess"
cp "$WORK/wine" "$WORK/ordinary-copy/cef_subprocess"
clang -O0 -DIMPOSTOR -o "$WORK/winetemp-other/cef_subprocess" "$WORK/wine.c"

cp "$ROOT/tests/core-test.swift" "$WORK/main.swift"
# the app finds compat/ by walking up from itself to the folder with scripts/build-engine.sh
mkdir -p "$WORK/bin"
ln -s "$ROOT/scripts" "$WORK/scripts"
ln -s "$ROOT/compat" "$WORK/compat"
swiftc -O -o "$WORK/bin/core-test" "$WORK/main.swift" "$SRC/Basics.swift" "$SRC/Settings.swift" "$SRC/VDF.swift" \
  "$SRC/Processes.swift" "$SRC/Diagnostics.swift" "$SRC/Library.swift" "$SRC/Bottles.swift" "$SRC/BottleSettings.swift" "$SRC/Engine.swift" \
  "$SRC/IsolatedWine.swift" "$SRC/PrefixLaunchGate.swift" "$SRC/Recipe.swift" "$SRC/Localization.swift" "$SRC/English.swift" 2>&1 \
  | grep -v "^$" || true
env -i WINEPREFIX="$WORK/bottles/steam" "$WORK/wine" 'C:\Program Files (x86)\Steam\steamapps\common\Game\bin\game.exe' -windowed &
FAKES+=($!); disown
env -i WINEPREFIX="$WORK/bottles/steam" "$WORK/wine" start.exe /exec /Users/someone/tool.exe &
FAKES+=($!); disown
env -i WINEPREFIX="$WORK/bottles/steam" "$WORK/winetemp-copy/cef_subprocess" 'C:\Games\WorldOfTanks.exe' &
FAKES+=($!); disown
env -i WINEPREFIX="$WORK/bottles/steam" "$WORK/winetemp-other/cef_subprocess" 'C:\Games\unrelated-cef.exe' &
FAKES+=($!); TRACKING_OTHER_PID=$!; disown
env -i WINEPREFIX="$WORK/bottles/steam" "$WORK/ordinary-copy/cef_subprocess" 'C:\Games\outside-temp.exe' &
FAKES+=($!); TRACKING_OUTSIDE_PID=$!; disown
sleep 0.5
EXPECT_PREFIX="$WORK/bottles/steam" EXPECT_COPIED_LOADER="$WORK/wine" EXPECT_UNRELATED_CEF_PID="$TRACKING_OTHER_PID" EXPECT_OUTSIDE_CEF_PID="$TRACKING_OUTSIDE_PID" "$WORK/bin/core-test"
