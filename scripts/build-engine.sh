#!/bin/bash
# Build the engine: CrossOver-derived Wine for macOS, x86_64 + i386 through the new WoW64.
#
# Source: dappermint/winecx at ENGINE_COMMIT = upstream wine 11.16 + CrossOver 26.3's changes
# + Proton's lsteamclient + FAudio update + ~1100 lines of local patches. Checked on 09/10/2026
# against wine-11.16, wine-11.0 + crossover-sources-26.3.0 and Proton db9e6ff;
# re-run that check whenever ENGINE_COMMIT moves.
#
# Layout (everything under engine/ is ignored by git):
#   src/          wine source tree at ENGINE_COMMIT
#   build-tools/  native arm64 makedep/winebuild/wrc/widl/wmc
#   build/        the x86_64 build
#   dist/         make install output
#   build.log     output of every run, appended
#
# Why the split: the tools run thousands of times per build. Built x86_64, every run is a
# Rosetta process, and macOS 27's ecosystemanalyticsd can pin the whole machine on that
# (frankea/winecx-gptk build notes). Built native, only configure probes go through Rosetta.
# The PE half uses mingw-w64 gcc: a kernelbase.dll built by llvm-mingw stalls Steam's CM login
# (same notes).
set -euo pipefail

ENGINE_REPO="https://github.com/dappermint/winecx"
ENGINE_COMMIT="7dbc5b5322a6ef3fb04bdc643c64b188fd641149"
# Vulkan for winevulkan (DXVK, and Chromium's ANGLE in Steam); digest from the GitHub release
MOLTENVK_VERSION="1.4.2"
MOLTENVK_SHA256="f95765a6229cb7b915990a2890ce12ebe36a730b021545d3d52ae69ce4c4024e"
# D3D9-11 on Vulkan, the last line that runs on MoltenVK (Gcenx's macOS build); Steam's own
# processes draw through it (recipes/steam.recipe). Hash as pinned by frankea/winecx-gptk.
DXVK_VERSION="1.10.3"
DXVK_URL="https://github.com/Gcenx/DXVK-macOS/releases/download/v1.10.3-20230507-repack/dxvk-macOS-async-v1.10.3-20230507-repack.tar.gz"
DXVK_SHA256="acd1520ad105d8ef124a09c8e11a259a5dc8bdc565ad18e0e52693f9807b2477"
# Windows components for programs (Visual C++ runtimes, .NET, fonts); release 20260125
WINETRICKS_COMMIT="b76e1ee79ac57d7aceb384f74518fc423265810c"
WINETRICKS_SHA256="431f82fc74000e6c864409f1d8fb495d696c03928808e3e8acffc45179312a7b"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/engine/src"
TOOLS="$ROOT/engine/build-tools"
BUILD="$ROOT/engine/build"
DIST="$ROOT/engine/dist"
X86=/usr/local          # x86_64 Homebrew: freetype, gnutls, sdl2, ffmpeg, gstreamer
ARM=/opt/homebrew       # arm64 Homebrew: bison, flex, make, mingw-w64, ccache, pkgconf, native freetype

mkdir -p "$ROOT/engine"
exec > >(tee -a "$ROOT/engine/build.log") 2>&1

NCPU="$(sysctl -n hw.logicalcpu)"
MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
# pkg-config search path per stage: that Homebrew's own .pc files plus its shims for the SDK's
# system libraries (zlib, bzip2 and friends, which freetype2.pc requires). Never the other
# Homebrew: the arm64 pkgconf looks into /usr/local by default.
ARM_PC="$ARM/lib/pkgconfig:$ARM/share/pkgconfig:$ARM/Library/Homebrew/os/mac/pkgconfig/$MACOS_MAJOR"
X86_PC="$X86/lib/pkgconfig:$X86/share/pkgconfig:$X86/Homebrew/Library/Homebrew/os/mac/pkgconfig/$MACOS_MAJOR"
# D3DMetal 4 itself needs macOS 15, so that is the floor
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-15.0}"
export SDKROOT="$(/usr/bin/xcrun --show-sdk-path)"
export PATH="$ARM/opt/bison/bin:$ARM/opt/flex/bin:$ARM/opt/make/libexec/gnubin:$ARM/bin:$PATH"
export CCACHE_DIR="$ROOT/engine/ccache"

step() { printf '\n==> %s (%s)\n' "$1" "$(date +%H:%M:%S)"; }

common_without=(--without-x --without-wayland --without-oss --without-alsa --without-pulse
                --without-sane --without-usb --without-v4l2 --without-pcap --without-capi
                --without-opencl --without-cups --disable-tests)

fetch() {
  step "fetch source $ENGINE_COMMIT"
  mkdir -p "$SRC"
  git -C "$SRC" init -q
  git -C "$SRC" remote get-url origin >/dev/null 2>&1 || git -C "$SRC" remote add origin "$ENGINE_REPO"
  git -C "$SRC" fetch -q --depth 1 origin "$ENGINE_COMMIT"
  git -C "$SRC" checkout -q --detach FETCH_HEAD
  cat "$SRC/VERSION"
}

tools() {
  step "native tools"
  mkdir -p "$TOOLS" && cd "$TOOLS"
  # without an explicit arch list a native configure defaults to aarch64 PE
  [ -f Makefile ] || CC="ccache /usr/bin/clang" PKG_CONFIG_LIBDIR="$ARM_PC" \
    "$SRC/configure" --enable-archs=i386,x86_64 --without-gstreamer --without-ffmpeg "${common_without[@]}"
  make -j"$NCPU" __tooldeps__
  # wrc resolves nls/ relative to its own binary and __tooldeps__ never fills it
  rm -rf nls && mkdir nls && ln -s "$SRC/nls/locale.nls" nls/locale.nls
  test -r nls/locale.nls
}

configure_x86() {
  step "configure x86_64"
  mkdir -p "$BUILD" && cd "$BUILD"
  export CC="ccache /usr/bin/clang -arch x86_64" CXX="ccache /usr/bin/clang++ -arch x86_64"
  # LIBDIR, not PATH: arm64 .pc files must never leak into the x86_64 build
  export PKG_CONFIG_LIBDIR="$X86_PC"
  export CFLAGS="-O2 -Wno-error=implicit-function-declaration -Werror=unguarded-availability-new -I$X86/include"
  export CROSSCFLAGS="-O2"
  export LDFLAGS="-L$X86/lib"
  # pipe2 is above the 15.0 floor; every call site has a pipe + fcntl fallback
  export ac_cv_func_pipe2=no
  export ac_cv_lib_soname_freetype=libfreetype.6.dylib
  export ac_cv_lib_soname_gnutls=libgnutls.30.dylib
  export ac_cv_lib_soname_MoltenVK=libMoltenVK.dylib
  "$SRC/configure" --host=x86_64-apple-darwin24 --with-wine-tools="$TOOLS" \
    --enable-archs=i386,x86_64 --prefix="$DIST" "${common_without[@]}"
  # configure only warns when these are missing; say it loudly instead
  grep -q '^#define HAVE_FFMPEG 1' include/config.h && echo "ffmpeg: found" || echo "WARNING: ffmpeg not found"
  grep -qE '^GSTREAMER_LIBS *= *.+' Makefile && echo "gstreamer: found" || echo "WARNING: gstreamer not found"
}

build_x86() {
  step "make"
  cd "$BUILD"
  make -j"$(( NCPU + NCPU / 2 ))"
  step "install"
  make install
  step "done"
}

# Wine Mono and Wine Gecko installers, at the versions and SHA-256 the source itself pins in
# dlls/appwiz.cpl/addons.c. appwiz checks the hash again before installing anything.
addons() {
  step "addons (wine-mono, wine-gecko)"
  local src="$SRC/dlls/appwiz.cpl/addons.c" share="$DIST/share/wine"
  local gecko mono
  gecko="$(sed -n 's/^#define GECKO_VERSION "\(.*\)"/\1/p' "$src")"
  mono="$(sed -n 's/^#define MONO_VERSION "\(.*\)"/\1/p' "$src")"
  # the SHA lines follow their arch block: x86 gecko, x86_64 gecko, x86 mono
  local -a shas
  shas=($(sed -nE 's/^#define (GECKO|MONO)_SHA "([0-9a-f]{64})"/\2/p' "$src"))
  [ "${#shas[@]}" -ge 3 ] || { echo "could not read addon hashes from $src"; exit 1; }
  fetch_addon "$share/gecko" "https://dl.winehq.org/wine/wine-gecko/$gecko/wine-gecko-$gecko-x86.msi" "${shas[0]}"
  fetch_addon "$share/gecko" "https://dl.winehq.org/wine/wine-gecko/$gecko/wine-gecko-$gecko-x86_64.msi" "${shas[1]}"
  fetch_addon "$share/mono" "https://dl.winehq.org/wine/wine-mono/$mono/wine-mono-$mono-x86.msi" "${shas[2]}"
}

moltenvk() {
  step "MoltenVK $MOLTENVK_VERSION"
  local tar="$ROOT/engine/deps/MoltenVK-macos-$MOLTENVK_VERSION.tar" tmp dylib
  mkdir -p "$ROOT/engine/deps"
  if [ ! -f "$tar" ] || [ "$(shasum -a 256 "$tar" | cut -d' ' -f1)" != "$MOLTENVK_SHA256" ]; then
    curl -sfL -o "$tar.part" "https://github.com/KhronosGroup/MoltenVK/releases/download/v$MOLTENVK_VERSION/MoltenVK-macos.tar"
    [ "$(shasum -a 256 "$tar.part" | cut -d' ' -f1)" = "$MOLTENVK_SHA256" ] || { rm -f "$tar.part"; echo "SHA-256 mismatch: MoltenVK"; exit 1; }
    mv "$tar.part" "$tar"
  fi
  tmp="$(mktemp -d)"
  tar -xf "$tar" -C "$tmp"
  dylib="$(find "$tmp" -path '*dynamic*' -name libMoltenVK.dylib | head -1)"
  [ -n "$dylib" ] || { rm -rf "$tmp"; echo "libMoltenVK.dylib not found in the release"; exit 1; }
  # winevulkan dlopens it by soname; run.sh puts engine/dist/lib on the dyld fallback path
  install -m 0644 "$dylib" "$DIST/lib/libMoltenVK.dylib"
  rm -rf "$tmp"
  echo "libMoltenVK.dylib: $(lipo -archs "$DIST/lib/libMoltenVK.dylib")"
}

winetricks() {
  step "winetricks"
  local target="$DIST/bin/winetricks"
  curl -sfL -o "$target.part" "https://raw.githubusercontent.com/Winetricks/winetricks/$WINETRICKS_COMMIT/src/winetricks"
  [ "$(shasum -a 256 "$target.part" | cut -d' ' -f1)" = "$WINETRICKS_SHA256" ] || { rm -f "$target.part"; echo "SHA-256 mismatch: winetricks"; exit 1; }
  mv "$target.part" "$target"
  chmod 755 "$target"
  echo "$(perl -ne 'print $1 if /^WINETRICKS_VERSION=(\S+)/' "$target") in $target"
}

# our cxcompatdb.so: per-executable D3DMetal (see engine/compat/cxcompatdb.c)
compat() {
  step "compat module"
  /usr/bin/clang -arch x86_64 -mmacosx-version-min="$MACOSX_DEPLOYMENT_TARGET" -dynamiclib -O2 -Wall \
    -o "$DIST/lib/wine/x86_64-unix/cxcompatdb.so" "$ROOT/engine/compat/cxcompatdb.c"
  echo "installed $DIST/lib/wine/x86_64-unix/cxcompatdb.so"
}

dxvk() {
  step "DXVK $DXVK_VERSION (macOS)"
  local tgz="$ROOT/engine/deps/$(basename "$DXVK_URL")" tmp top
  mkdir -p "$ROOT/engine/deps"
  if [ ! -f "$tgz" ] || [ "$(shasum -a 256 "$tgz" | cut -d' ' -f1)" != "$DXVK_SHA256" ]; then
    curl -sfL -o "$tgz.part" "$DXVK_URL"
    [ "$(shasum -a 256 "$tgz.part" | cut -d' ' -f1)" = "$DXVK_SHA256" ] || { rm -f "$tgz.part"; echo "SHA-256 mismatch: DXVK"; exit 1; }
    mv "$tgz.part" "$tgz"
  fi
  tmp="$(mktemp -d)"
  tar -xzf "$tgz" -C "$tmp"
  top="$(find "$tmp" -maxdepth 2 -type d -name x64 -exec dirname {} \; | head -1)"
  [ -n "$top" ] && [ -f "$top/x64/d3d11.dll" ] && [ -f "$top/x32/d3d11.dll" ] || { rm -rf "$tmp"; echo "unexpected DXVK layout"; exit 1; }
  rm -rf "$DIST/lib/dxvk"
  mkdir -p "$DIST/lib/dxvk"
  ditto "$top/x64" "$DIST/lib/dxvk/x64"
  ditto "$top/x32" "$DIST/lib/dxvk/x32"
  rm -rf "$tmp"
  echo "DXVK: $(ls "$DIST/lib/dxvk/x64" | tr '\n' ' ')"
}

# GStreamer's FFmpeg plugin (gst-libav) for game videos in WMV, WMA, MPEG-2 and the like.
# Homebrew's x86_64 copy is built against an older FFmpeg than the one it ships, so it does not
# load; this builds FFmpeg 7.1 ourselves, LGPL and decoders only (no encoders, network or
# devices), and gst-libav 1.26.0 against it and Homebrew's GStreamer 1.26.0, into deps/media.
# tools/bundle-libs.py then carries them into the portable engine.
FFMPEG_VERSION=7.1.2
FFMPEG_SHA256=089bc60fb59d6aecc5d994ff530fd0dcb3ee39aa55867849a2bbc4e555f9c304
GSTLIBAV_VERSION=1.26.0
GSTLIBAV_SHA256=707a8b687ff5fddcee5b02415e2ec9b71b4ac44d0b7aec3b477364ceecbf1ecf
media() {
  step "media: FFmpeg $FFMPEG_VERSION + gst-libav $GSTLIBAV_VERSION"
  local deps="$ROOT/engine/deps" prefix="$ROOT/engine/deps/media" work="$ROOT/engine/build/media"
  fetch_addon "$deps" "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz" "$FFMPEG_SHA256"
  fetch_addon "$deps" "https://gstreamer.freedesktop.org/src/gst-libav/gst-libav-$GSTLIBAV_VERSION.tar.xz" "$GSTLIBAV_SHA256"
  rm -rf "$work" "$prefix"
  mkdir -p "$work"
  tar -xf "$deps/ffmpeg-$FFMPEG_VERSION.tar.xz" -C "$work"
  tar -xf "$deps/gst-libav-$GSTLIBAV_VERSION.tar.xz" -C "$work"
  (cd "$work/ffmpeg-$FFMPEG_VERSION" && ./configure --prefix="$prefix" --enable-cross-compile --arch=x86_64 \
      --target-os=darwin --cc="clang -arch x86_64" --cxx="clang++ -arch x86_64" \
      --extra-cflags="-mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET" --extra-ldflags="-mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET" \
      --enable-shared --disable-static --disable-programs --disable-doc --disable-network --disable-x86asm \
      --disable-encoders --disable-muxers --disable-devices --disable-avdevice --disable-postproc \
      --disable-iconv --disable-securetransport --disable-videotoolbox --disable-audiotoolbox --disable-sdl2 \
      --disable-lzma --disable-xlib --disable-libxcb \
    && make -j"$(sysctl -n hw.ncpu)" && make install)
  # meson and ninja for gst-libav, in a venv of their own
  local venv="$ROOT/engine/build-tools/venv"
  [ -x "$venv/bin/meson" ] || { python3 -m venv "$venv" && "$venv/bin/pip" install -q meson ninja; }
  cat > "$work/x86_64.ini" <<INI
[binaries]
c = ['clang', '-arch', 'x86_64', '-mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET']
cpp = ['clang++', '-arch', 'x86_64', '-mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET']
objc = ['clang', '-arch', 'x86_64', '-mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET']
ar = 'ar'
strip = 'strip'
pkg-config = '$X86/bin/pkg-config'
[properties]
pkg_config_libdir = ['$prefix/lib/pkgconfig', '$X86_PC']
[host_machine]
system = 'darwin'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
INI
  (cd "$work/gst-libav-$GSTLIBAV_VERSION" \
    && PATH="$venv/bin:$PATH" meson setup build --cross-file "$work/x86_64.ini" --prefix="$prefix" \
         -Ddoc=disabled -Dtests=disabled \
    && PATH="$venv/bin:$PATH" ninja -C build && PATH="$venv/bin:$PATH" ninja -C build install)
  echo "installed $prefix/lib/gstreamer-1.0/libgstlibav.dylib"
}

# A copy of dist/ that runs on a Mac without Homebrew, for the app to carry: tools/bundle-libs.py
# brings in the libraries wine opens and links, with a set of GStreamer plugins; cabextract comes
# along for winetricks. D3DMetal stays out (every user imports their own), and so do the static
# libraries only building against wine needs.
portable() {
  step "portable engine"
  local out="$ROOT/engine/portable"
  rm -rf "$out"
  mkdir -p "$out"
  rsync -a --exclude 'lib/apple_gptk/' --exclude '*.a' --exclude 'include/' --exclude 'share/man/' \
    --exclude 'share/applications/' "$DIST/" "$out/"
  # links left by an old in-place D3DMetal install point at nothing
  find -L "$out" -type l -exec rm -f {} +
  python3 -I "$ROOT/tools/bundle-libs.py" "$out"
  cp "$(command -v cabextract)" "$out/bin/cabextract"
  printf '{"wine": "%s", "portable": true, "built": "%s"}\n' "$("$out/bin/wine" --version)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    > "$out/engine.json"
  echo "engine at $out ($(du -sh "$out" | cut -f1))"
}

# Windows helpers of our own: the Discord bridge, which relays a game's Discord pipe to the
# Discord app on the Mac (engine/discord-bridge/bridge.c), and the audio check that plays a short
# tone through Windows audio (engine/audio-test/audio-test.c)
discord() {
  step "windows helpers"
  mkdir -p "$DIST/lib/exerunner"
  x86_64-w64-mingw32-gcc -O2 -Wall -Wextra -mwindows -static -s \
    -o "$DIST/lib/exerunner/discord-bridge.exe" "$ROOT/engine/discord-bridge/bridge.c"
  x86_64-w64-mingw32-gcc -O2 -Wall -static -s \
    -o "$DIST/lib/exerunner/audio-test.exe" "$ROOT/engine/audio-test/audio-test.c" -lwinmm -lm
  echo "installed $DIST/lib/exerunner/discord-bridge.exe and audio-test.exe"
}

fetch_addon() {
  local dir="$1" url="$2" sha="$3" file
  file="$dir/$(basename "$url")"
  mkdir -p "$dir"
  if [ ! -f "$file" ] || [ "$(shasum -a 256 "$file" | cut -d' ' -f1)" != "$sha" ]; then
    curl -sfL -o "$file.part" "$url"
    [ "$(shasum -a 256 "$file.part" | cut -d' ' -f1)" = "$sha" ] || { rm -f "$file.part"; echo "SHA-256 mismatch: $url"; exit 1; }
    mv "$file.part" "$file"
  fi
  echo "ok $(basename "$file")"
}

case "${1:-all}" in
  fetch) fetch ;;
  tools) tools ;;
  configure) configure_x86 ;;
  make) build_x86 ;;
  addons) addons ;;
  moltenvk) moltenvk ;;
  dxvk) dxvk ;;
  compat) compat ;;
  discord) discord ;;
  media) media ;;
  portable) portable ;;
  winetricks) winetricks ;;
  all) [ -f "$SRC/VERSION" ] || fetch; tools; configure_x86; build_x86; addons; moltenvk; dxvk; winetricks; compat; discord; media; portable ;;
  *) echo "usage: $0 [fetch|tools|configure|make|addons|moltenvk|dxvk|winetricks|compat|discord|media|portable|all]"; exit 2 ;;
esac
