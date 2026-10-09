#!/bin/bash
# Deploy Apple's D3DMetal payload next to the built engine (engine/dist/lib/apple_gptk).
#
# usage: deploy-gptk.sh <redist-dir> | --remove
#   <redist-dir>  the evaluation environment's redist/ folder (contains lib/external and lib/wine)
#   --remove      take the payload out again
#
# Wine's own d3d10/d3d11/d3d12/dxgi stay where they are. Our cxcompatdb.so (engine/compat)
# prepends apple_gptk/wine to the builtin DLL path in each process that should get D3DMetal,
# which is every process except the executables the launcher lists in WINRUNNER_D3DMETAL_SKIP.
# Same layout as CrossOver's lib64/apple_gptk.
#
# Nothing of Apple's lives in git: the user brings their own download. The payload's unix
# modules are symlinks to ../../external/libd3dshared.dylib, and that dylib finds
# D3DMetal.framework through @loader_path, so the tree is copied with ditto, which keeps
# symlinks as symlinks.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$ROOT/engine/dist/lib"
GPTK="$LIB/apple_gptk"

[ -x "$ROOT/engine/dist/bin/wine" ] || { echo "no engine in engine/dist, run build-engine.sh first"; exit 1; }
[ -e "$LIB/wine/x86_64-unix/cxcompatdb.so" ] || { echo "no cxcompatdb.so, run build-engine.sh compat first"; exit 1; }

# an earlier version copied the payload over wine's own DLLs; undo that
undo_in_place() {
  local backup="$LIB/.wine-originals" arch f
  [ -d "$backup" ] || return 0
  rm -rf "$LIB/external"
  for arch in x86_64-windows x86_64-unix; do
    for f in "$LIB/wine/$arch"/{nvapi64,nvngx,nvngx-on-metalfx}.{dll,so}; do
      if [ -e "$f" ] || [ -L "$f" ]; then rm -f "$f"; fi
    done
    [ -d "$backup/$arch" ] && ditto "$backup/$arch" "$LIB/wine/$arch"
  done
  rm -rf "$backup"
  echo "restored wine's own d3d10/d3d11/d3d12/dxgi"
}

undo_in_place

if [ "${1:-}" = "--remove" ]; then
  rm -rf "$GPTK"
  echo "D3DMetal removed"
  exit 0
fi

SRC="${1:?usage: deploy-gptk.sh <redist-dir> | --remove}/lib"
for f in external/libd3dshared.dylib external/D3DMetal.framework \
         wine/x86_64-windows/d3d11.dll wine/x86_64-windows/d3d12.dll wine/x86_64-windows/dxgi.dll \
         wine/x86_64-unix/d3d12.so; do
  [ -e "$SRC/$f" ] || { echo "not a D3DMetal redist: missing $f"; exit 1; }
done
[ -L "$SRC/wine/x86_64-unix/d3d12.so" ] || { echo "unix modules must be symlinks; copy the redist with ditto, not cp -L"; exit 1; }

rm -rf "$GPTK"
mkdir -p "$GPTK"
ditto "$SRC/external" "$GPTK/external"
ditto "$SRC/wine" "$GPTK/wine"

# DLSS through MetalFX: the payload ships the bridge under another name (Apple's Read Me)
ln -sf ../../external/libd3dshared.dylib "$GPTK/wine/x86_64-unix/nvngx.so"
cp -f "$GPTK/wine/x86_64-windows/nvngx-on-metalfx.dll" "$GPTK/wine/x86_64-windows/nvngx.dll"

version="$(defaults read "$GPTK/external/D3DMetal.framework/Resources/Info.plist" CFBundleShortVersionString 2>/dev/null || echo unknown)"
echo "$version" > "$GPTK/D3DMETAL_VERSION"
echo "D3DMetal $version deployed into $GPTK"
