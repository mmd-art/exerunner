#!/bin/bash
# Capture the native Mac window of our own 32-bit D3D9 program. A backbuffer
# readback or a successful Present HRESULT cannot prove that a window displays.
# Requires existing screen-capture permission; no third-party program is executed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE="${1:-/Applications/ExeRunner.app/Contents/Resources/engine}"
WORK="$(mktemp -d /private/tmp/exerunner-present.XXXXXX)"
PREFIX="$WORK/isolated-present"
wine_env() {
  /usr/bin/env -i WINEPREFIX="$PREFIX" HOME="$PREFIX/.isolation/home" TMPDIR="$PREFIX/.isolation/tmp" PATH=/usr/bin:/bin \
    WINEMSYNC=0 WINEDLLOVERRIDES=winemenubuilder.exe=d WINEDEBUG=-all,err+d3d \
    EXERUNNER_SANDBOX_PROFILE="$WORK/profile.sb" WINEDLLPATH="$ENGINE/lib/wine" \
    WINE_APP_DISPLAY_NAME="ExeRunner controlled Direct3D9 check" WINE_APP_DOCK_EXE=present32.exe WINE_APP_IDENTITY_EXE=present32.exe WINE_APP_GAME=1 \
    DYLD_FALLBACK_LIBRARY_PATH="$ENGINE/lib:/usr/lib" "$@"
}
cleanup() {
  if [ -x "$WORK/window-check" ]; then "$WORK/window-check" stop "$PREFIX" >/dev/null || true; fi
  wine_env "$ENGINE/bin/wineserver" -k >/dev/null 2>&1 || true
  if [ "${EXERUNNER_KEEP_PRESENT_EVIDENCE:-0}" = 1 ]; then rm -rf "$PREFIX"; else rm -rf "$WORK"; fi
}
trap cleanup EXIT
mkdir -p "$PREFIX/drive_c" "$PREFIX/.isolation/home" "$PREFIX/.isolation/tmp" "$WORK/window"
printf 'offline prototype\n' > "$PREFIX/.exerunner-isolated-v1"
SRC="$ROOT/app/Sources/ExeRunner/Core"
cp "$ROOT/tests/isolation-test.swift" "$WORK/main.swift"
swiftc -o "$WORK/harness" "$WORK/main.swift" "$SRC/IsolatedWine.swift" "$SRC/Basics.swift" "$SRC/Engine.swift" "$SRC/Library.swift" "$SRC/Bottles.swift" "$SRC/Settings.swift" "$SRC/Processes.swift" "$SRC/VDF.swift" "$SRC/Recipe.swift" "$SRC/Localization.swift" "$SRC/English.swift" "$SRC/PrefixLaunchGate.swift"
cp "$ROOT/tests/isolation-present-window.swift" "$WORK/window/main.swift"
swiftc -O "$WORK/window/main.swift" "$SRC/Processes.swift" -o "$WORK/window-check"
i686-w64-mingw32-gcc -O2 -static "$ROOT/tests/isolation-present.c" -ld3d9 -o "$PREFIX/drive_c/present32.exe"
"$WORK/harness" profile "$PREFIX" "$ENGINE" "$WORK/profile.sb"
wine_env /usr/bin/sandbox-exec -f "$WORK/profile.sb" /usr/bin/env "DYLD_FALLBACK_LIBRARY_PATH=$ENGINE/lib:/usr/lib" \
  "$ENGINE/bin/wine" wineboot --init > "$WORK/boot.log" 2>&1
wine_env "$ENGINE/bin/wineserver" -w
RENDER_ENV=()
if [ "${EXERUNNER_TEST_VULKAN:-0}" = 1 ]; then
  wine_env /usr/bin/sandbox-exec -f "$WORK/profile.sb" /usr/bin/env "DYLD_FALLBACK_LIBRARY_PATH=$ENGINE/lib:/usr/lib" \
    "$ENGINE/bin/wine" reg add 'HKCU\Software\Wine\Direct3D' /v renderer /d vulkan /f >> "$WORK/boot.log" 2>&1
  RENDER_ENV+=(MTL_HUD_ENABLED=1)
fi
wine_env /usr/bin/sandbox-exec -f "$WORK/profile.sb" /usr/bin/env "DYLD_FALLBACK_LIBRARY_PATH=$ENGINE/lib:/usr/lib" "${RENDER_ENV[@]}" \
  "$ENGINE/bin/wine" "$PREFIX/drive_c/present32.exe" > "$WORK/present.log" 2>&1 &
PRESENT_PID=$!
WINDOW_ID=""
for attempt in {1..80}; do
  WINDOW_ID="$("$WORK/window-check" window "$PREFIX" || true)"
  if [ -n "$WINDOW_ID" ]; then break; fi
  sleep 0.25
done
if [ -z "$WINDOW_ID" ]; then echo 'FAIL: no native window' >&2; exit 1; fi
VISIBLE_ID=""
for attempt in {1..40}; do
  VISIBLE_ID="$("$WORK/window-check" onscreen "$PREFIX" || true)"
  if [ "$VISIBLE_ID" = "$WINDOW_ID" ]; then break; fi
  sleep 0.25
done
if [ "$VISIBLE_ID" != "$WINDOW_ID" ]; then echo 'FAIL: native window is not on the current desktop' >&2; exit 1; fi
echo "ONSCREEN_WINDOW=$VISIBLE_ID"
for attempt in {1..40}; do
  if rg -q 'DEVICE=00000000' "$WORK/present.log"; then break; fi
  sleep 0.25
done
sleep 3
/usr/sbin/screencapture -x -l "$WINDOW_ID" "$WORK/native-window.png"
"$WORK/window-check" pixel "$WORK/native-window.png"
if [ "${EXERUNNER_VERIFY_INPUT:-0}" = 1 ]; then
  "$WORK/window-check" input "$PREFIX" | tee "$WORK/input-expected.log"
fi
wait "$PRESENT_PID"
wine_env "$ENGINE/bin/wineserver" -w
if rg -q 'FBO 0 is incomplete|GL_INVALID_FRAMEBUFFER_OPERATION' "$WORK/present.log"; then
  echo 'FAIL: native drawable errors' >&2; exit 1
fi
rg 'PTR_BITS=32|PRESENT=' "$WORK/present.log"
if [ "${EXERUNNER_VERIFY_INPUT:-0}" = 1 ]; then
  python3 - "$WORK" <<'INPUT_CHECK'
import pathlib,re,sys
work=pathlib.Path(sys.argv[1])
expected=[tuple(map(int,p.split(','))) for p in re.findall(r'EXPECTED_MOUSE=([0-9]+,[0-9]+)',(work/'input-expected.log').read_text())]
actual=[tuple(map(int,p)) for p in re.findall(r'INPUT_MOUSE=513,([0-9]+),([0-9]+)',(work/'present.log').read_text())]
assert len(expected)==2 and all(any(abs(x-ax)<=1 and abs(y-ay)<=1 for ax,ay in actual) for x,y in expected),(expected,actual)
assert 'INPUT_KEY=75' in (work/'present.log').read_text(),'Native keyboard input not delivered'
print('PASS: native focus, two mouse click coordinates and keyboard delivery')
INPUT_CHECK
fi
echo "PASS: visible native 32-bit D3D9 window with rendered pixels; keyboard focus acceptance is separate; evidence $WORK"
