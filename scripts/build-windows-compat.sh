#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CC="${EXERUNNER_MINGW_CC:-x86_64-w64-mingw32-gcc}"
command -v "$CC" >/dev/null || { echo "missing Windows cross compiler: $CC" >&2; exit 1; }
OUT="$ROOT/compat/windows"
mkdir -p "$OUT"
"$CC" -O1 -fno-builtin -fno-stack-protector -nostdlib -shared \
  -Wl,--entry,DllMain,--image-base,0x65000000 \
  -o "$OUT/execution-breakpoints.dll" "$ROOT/tools/windows/execution-breakpoints.c" -lkernel32
"$CC" -O1 -fno-builtin -fno-stack-protector -nostdlib \
  -Wl,--entry,mainCRTStartup -o "$OUT/compat-launcher.exe" "$ROOT/tools/windows/compat-launcher.c" -lkernel32
