#!/bin/bash
# Checks cxcompatdb.c's decisions outside wine: the module is compiled into a test program named
# game.exe, whose prepend_dll_path() records whether D3DMetal would be put first for it.
set -euo pipefail
if [ -z "${EXERUNNER_ARTIFACT_SESSION:-}" ]; then
  exec python3 -I "$(cd "$(dirname "$0")/.." && pwd)/tools/artifacts.py" run --label test-cxcompatdb-test -- bash "$0" "$@"
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/main.c" <<'C'
#include <stdio.h>
#include <stdlib.h>
static int called;
void prepend_dll_path(const char *dir) { called = 1; (void)dir; }
int main(void)
{
    const char *foo = getenv("FOO");
    printf("d3dmetal=%s foo=%s\n", called ? "on" : "off", foo ? foo : "-");
    return 0;
}
C
clang -O0 -o "$WORK/game.exe" "$WORK/main.c" "$ROOT/engine/compat/cxcompatdb.c"

pass=0; fail=0
expect() {
  local name="$1" want="$2"; shift 2
  local got
  got="$(env -i "$@" "$WORK/game.exe")"
  if [ "$got" = "$want" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL $name: got '$got', want '$want'"; fi
}

D=EXERUNNER_D3DMETAL_DIR=/x
expect "no D3DMetal dir" "d3dmetal=off foo=-"
expect "D3DMetal, nothing else" "d3dmetal=on foo=-" "$D"
expect "skip list without a file" "d3dmetal=off foo=-" "$D" EXERUNNER_D3DMETAL_SKIP=a.exe,GAME.EXE
expect "skip list names another program" "d3dmetal=on foo=-" "$D" EXERUNNER_D3DMETAL_SKIP=a.exe
printf 'game.exe\t@d3dmetal=off\nother.exe\tFOO=no\n' > "$WORK/off"
expect "file turns it off" "d3dmetal=off foo=-" "$D" EXERUNNER_COMPAT_FILE="$WORK/off"
: > "$WORK/empty"
expect "file is newer than a stale skip list" "d3dmetal=on foo=-" "$D" EXERUNNER_COMPAT_FILE="$WORK/empty" EXERUNNER_D3DMETAL_SKIP=game.exe
printf 'Game.exe\tFOO=bar baz\n' > "$WORK/env"
expect "file sets variables, any case" "d3dmetal=on foo=bar baz" "$D" EXERUNNER_COMPAT_FILE="$WORK/env"
expect "missing file falls back to the list" "d3dmetal=off foo=-" "$D" EXERUNNER_COMPAT_FILE="$WORK/none" EXERUNNER_D3DMETAL_SKIP=game.exe
expect "DXMT without file" "d3dmetal=on foo=-" EXERUNNER_DXMT_DIR=/dxmt EXERUNNER_USE_DXMT=1
expect "stale inherited DXMT does not affect child" "d3dmetal=on foo=-" "$D" EXERUNNER_DXMT_DIR=/dxmt EXERUNNER_USE_DXMT=1 EXERUNNER_COMPAT_FILE="$WORK/empty"
printf 'game.exe\t@d3dmetal=off\ngame.exe\t@dxmt=on\n' > "$WORK/dxmt"
expect "selected executable loads builtin DXMT" "d3dmetal=on foo=-" "$D" EXERUNNER_DXMT_DIR=/dxmt EXERUNNER_COMPAT_FILE="$WORK/dxmt"
expect "missing DXMT never falls back to D3DMetal" "d3dmetal=off foo=-" "$D" EXERUNNER_COMPAT_FILE="$WORK/dxmt"
cat > "$WORK/path.c" <<'C'
#include <stdio.h>
static const char *chosen = "none";
void prepend_dll_path(const char *dir) { chosen = dir; }
int main(void) { puts(chosen); return 0; }
C
clang -O0 -o "$WORK/game.exe" "$WORK/path.c" "$ROOT/engine/compat/cxcompatdb.c"
expect "actual DXMT path" "/dxmt" "$D" EXERUNNER_DXMT_DIR=/dxmt EXERUNNER_COMPAT_FILE="$WORK/dxmt"
expect "D3DMetal path remains untouched" "/x" "$D" EXERUNNER_DXMT_DIR=/dxmt EXERUNNER_COMPAT_FILE="$WORK/empty"
expect "inherited choice cannot switch unrelated program" "/x" "$D" EXERUNNER_DXMT_DIR=/dxmt EXERUNNER_USE_DXMT=1 EXERUNNER_COMPAT_FILE="$WORK/empty"
cat > "$WORK/modeset.c" <<'C'
#include <stdio.h>
#include <stdlib.h>
static const char *chosen = "none";
void prepend_dll_path(const char *dir) { chosen = dir; }
int main(void) {
    const char *mode = getenv("EXERUNNER_EMULATE_MODESET");
    printf("%s modeset=%s\n", chosen, mode ? mode : "-");
    return 0;
}
C
clang -O0 -o "$WORK/game.exe" "$WORK/modeset.c" "$ROOT/engine/compat/cxcompatdb.c"
expect "DXMT opts into emulated Retina mode" "/dxmt modeset=1" "$D" EXERUNNER_DXMT_DIR=/dxmt EXERUNNER_COMPAT_FILE="$WORK/dxmt"
expect "unrelated child clears inherited DXMT modeset" "/x modeset=-" "$D" EXERUNNER_DXMT_DIR=/dxmt EXERUNNER_EMULATE_MODESET=1 EXERUNNER_COMPAT_FILE="$WORK/empty"
expect "Wine child clears inherited DXMT modeset" "none modeset=-" "$D" EXERUNNER_EMULATE_MODESET=1 EXERUNNER_COMPAT_FILE="$WORK/off"
expect "direct DXMT opts into emulated Retina mode" "/dxmt modeset=1" EXERUNNER_DXMT_DIR=/dxmt EXERUNNER_USE_DXMT=1
expect "regular Metal leaves modeset unchanged" "/x modeset=-" "$D"
echo "cxcompatdb: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
