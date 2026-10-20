#!/bin/bash
# Build ExeRunner.app into build/app.noindex/ (never into /Applications).
# Exclude this checkout from Spotlight and unregister the generated app on exit.
#
# usage: build-app.sh [debug|release] [--without-d3dmetal]
# Signs with the certificate named in $CODESIGN_IDENTITY or in scripts/signing.local (one line, not
# in git), so macOS keeps the app's permissions between builds; otherwise ad hoc. The engine goes inside when
# engine/portable exists (scripts/build-engine.sh portable): the app then needs nothing else.
set -euo pipefail
if [ -z "${EXERUNNER_ARTIFACT_SESSION:-}" ]; then
  exec python3 -I "$(cd "$(dirname "$0")/.." && pwd)/tools/artifacts.py" run --label build-app --exclusive build -- bash "$0" "$@"
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="ExeRunner"
if [ -n "${EXERUNNER_BUILD_ENGINE_ROOT:-}" ]; then
  ENGINE_SOURCE="$EXERUNNER_BUILD_ENGINE_ROOT"
  KEEP_ENGINE_SIGNATURES="${EXERUNNER_KEEP_ENGINE_SIGNATURES:-0}"
else
  # A damaged checked engine is an error, never a silent fallback to an older one.
  ENGINE_SOURCE="$(python3 -I "$ROOT/tools/artifacts.py" engine)"
  if [ "$ENGINE_SOURCE" = "$ROOT/engine/portable" ]; then
    KEEP_ENGINE_SIGNATURES="${EXERUNNER_KEEP_ENGINE_SIGNATURES:-0}"
  else
    KEEP_ENGINE_SIGNATURES="${EXERUNNER_KEEP_ENGINE_SIGNATURES:-1}"
  fi
fi
CONFIG="release"
export MACOSX_DEPLOYMENT_TARGET=15.0
WITH_D3DMETAL="${EXERUNNER_D3DMETAL:-1}"
for arg in "$@"; do
  case "$arg" in
    debug|release) CONFIG="$arg" ;;
    --without-d3dmetal) WITH_D3DMETAL=0 ;;
    *) echo "usage: $0 [debug|release] [--without-d3dmetal]"; exit 2 ;;
  esac
done
APP="$ROOT/build/app.noindex/$NAME.app"
# Check before creating a bundle: a restricted agent sandbox may not reach Spotlight.
python3 -I "$ROOT/tools/search-privacy.py" exclude-project
cleanup_registration() {
  local status=$?
  if [ -d "$APP" ]; then
    if ! python3 -I "$ROOT/tools/search-privacy.py" unregister-build "$APP"; then
      echo "could not remove the build app from macOS search; build is not ready" >&2
      status=1
    fi
  fi
  return "$status"
}
trap cleanup_registration EXIT
IDENTITY="${CODESIGN_IDENTITY:-$(cat "$ROOT/scripts/signing.local" 2>/dev/null || true)}"

bash "$ROOT/scripts/build-windows-compat.sh"
# Universal UI; Wine remains x86_64 on both hosts. Intel requires separate acceptance.
APP_ARCHS="${EXERUNNER_APP_ARCHS:-arm64 x86_64}"
ARCH_ARGS=()
for arch in $APP_ARCHS; do
  case "$arch" in arm64|x86_64) ARCH_ARGS+=(--arch "$arch") ;; *) echo "unsupported app architecture: $arch" >&2; exit 2 ;; esac
done
[ "${#ARCH_ARGS[@]}" -gt 0 ] || { echo 'no app architectures selected' >&2; exit 2; }
swift build --package-path "$ROOT/app" --scratch-path "$EXERUNNER_WORK_ROOT/swiftpm" -c "$CONFIG" "${ARCH_ARGS[@]}"
BIN="$(swift build --package-path "$ROOT/app" --scratch-path "$EXERUNNER_WORK_ROOT/swiftpm" -c "$CONFIG" "${ARCH_ARGS[@]}" --show-bin-path)/$NAME"

rm -rf "$APP" "$ROOT/build/$NAME.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$NAME"
ditto "$ROOT/recipes" "$APP/Contents/Resources/recipes"
ditto "$ROOT/compat" "$APP/Contents/Resources/compat"
cp "$ROOT/LICENSE" "$ROOT/CREDITS.md" "$APP/Contents/Resources/"
if [ -d "$ROOT/licenses/third-party" ]; then
  ditto "$ROOT/licenses/third-party" "$APP/Contents/Resources/ThirdPartyNotices"
fi
if [ -f "$ENGINE_SOURCE/engine.json" ]; then
  python3 -I "$ROOT/tools/check-portable.py" "$ENGINE_SOURCE" --minimum "$MACOSX_DEPLOYMENT_TARGET"
  ditto "$ENGINE_SOURCE" "$APP/Contents/Resources/engine"
fi
# D3DMetal goes in for free builds: Apple's Game Porting Toolkit licence lets it be passed on
# non-commercially, with Apple's notices (sections 2A(iii) and 2C). --without-d3dmetal, or
# EXERUNNER_D3DMETAL=0, leaves it out; users then import Apple's download in the app. It comes
# from this Mac's import, which carries the notices.
GPTK="$HOME/Library/Application Support/$NAME/D3DMetal"
if [ "$WITH_D3DMETAL" = 1 ]; then
  if [ -f "$GPTK/external/libd3dshared.dylib" ] && [ -f "$GPTK/Apple License.rtf" ]; then
    ditto "$GPTK" "$APP/Contents/Resources/d3dmetal"
    echo "D3DMetal $(cat "$GPTK/D3DMETAL_VERSION") inside, with Apple's notices"
  else
    echo "no D3DMetal with Apple's notices at $GPTK: import Game Porting Toolkit in the app first; building without it"
  fi
fi

# the icon: app/Resources/AppIcon.png (1024, on Apple's icon grid) at every size macOS asks for
ICONSET="$ROOT/build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ROOT/app/Resources/AppIcon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z "$((size * 2))" "$((size * 2))" "$ROOT/app/Resources/AppIcon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>local.exerunner.app</string>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>0.5.1</string>
  <key>CFBundleVersion</key><string>$(date +%Y%m%d%H%M)</string>
  <key>ExeRunnerSourceRevision</key><string>$(git -C "$ROOT" rev-parse HEAD)</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>GPL-3.0-or-later</string>
</dict>
</plist>
PLIST

# by hash: the keychain can hold several certificates with this name, only one of them valid
HASH=""
if [ -n "$IDENTITY" ]; then
  HASH="$(security find-identity -v -p codesigning | awk -v name="\"$IDENTITY\"" 'index($0, name) { print $2; exit }')"
fi
SIGN="${HASH:--}"
# the engine's own programs and libraries first, then the app that seals them
if [ -d "$APP/Contents/Resources/engine" ] && [ "$KEEP_ENGINE_SIGNATURES" = 1 ]; then
  # Reuse a previously verified engine without rewriting its signed Mach-O files.
  codesign --verify --strict "$APP/Contents/Resources/engine/bin/wine"
fi
if [ -d "$APP/Contents/Resources/engine" ] && [ "$KEEP_ENGINE_SIGNATURES" != 1 ]; then
  python3 -I - "$APP/Contents/Resources/engine" <<'PY' | xargs -0 codesign --force --sign "$SIGN"
import os, sys
magics = (b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xce\xfa\xed\xfe")
for root, _, files in os.walk(sys.argv[1]):
    for name in files:
        path = os.path.join(root, name)
        if os.path.islink(path):
            continue
        with open(path, "rb") as f:
            if f.read(4) in magics:
                sys.stdout.write(path + "\0")
PY
fi
codesign --force --sign "$SIGN" "$APP"
codesign --verify --strict "$APP"
python3 -I "$ROOT/tools/check-portable.py" "$APP" --minimum "$MACOSX_DEPLOYMENT_TARGET"
# The EXIT trap verifies removal from LaunchServices, also after a failed build.
echo "built $APP"
