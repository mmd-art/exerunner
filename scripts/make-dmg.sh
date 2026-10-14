#!/bin/bash
# Packs build/app.noindex/ExeRunner.app (with its engine inside; scripts/build-engine.sh portable, then
# build-app.sh) into build/ExeRunner-<version>.dmg to hand to friends: the app and a link to
# /Applications to drag it onto, with a note on opening it in Russian and English. D3DMetal is in it
# when build-app.sh put it in the app; otherwise the note says where to get it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/app.noindex/ExeRunner.app"
[ -f "$APP/Contents/Resources/engine/engine.json" ] || { echo "no engine inside $APP: run build-engine.sh portable, then build-app.sh"; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$ROOT/build/ExeRunner-$VERSION.dmg"
python3 -I "$ROOT/tools/search-privacy.py" exclude-project
# Stage inside the excluded checkout, including newly generated bundles.
STAGE="$(mktemp -d "$ROOT/build/app.noindex/.dmg-stage.XXXXXX")"
cleanup_stage() {
  local status=$?
  if [ -d "$STAGE/ExeRunner.app" ]; then
    if ! python3 -I "$ROOT/tools/search-privacy.py" unregister-build "$STAGE/ExeRunner.app"; then
      echo "could not remove the DMG staging app from macOS search" >&2
      status=1
    fi
  fi
  rm -rf "$STAGE"
  return "$status"
}
trap cleanup_stage EXIT

ditto "$APP" "$STAGE/ExeRunner.app"
ln -s /Applications "$STAGE/Applications"
if [ -d "$APP/Contents/Resources/d3dmetal" ]; then
  D3DM="D3DMetal от Apple уже внутри; новую версию можно подключить из Game Porting Toolkit"
  D3DM_EN="Apple's D3DMetal is already inside; a newer one can be connected from the Game Porting Toolkit"
else
  D3DM="D3DMetal: скачай Game Porting Toolkit на developer.apple.com (вход по Apple ID, бесплатно)
   и перетащи .dmg в окно ExeRunner"
  D3DM_EN="D3DMetal: download the Game Porting Toolkit at developer.apple.com (Apple ID sign-in, free)
   and drag the .dmg onto the ExeRunner window"
fi
cat > "$STAGE/Как открыть.txt" <<TXT
1. Перетащи ExeRunner в папку «Программы» (Applications).
2. Первый раз открой его правой кнопкой мыши → «Открыть»: macOS не знает этого разработчика.
   Если она всё равно не даёт: «Системные настройки» → «Конфиденциальность и безопасность» →
   внизу «Всё равно открыть».
3. Дальше ExeRunner сам проведёт по шагам: Rosetta, лаунчеры.
   $D3DM.
TXT
cat > "$STAGE/How to open.txt" <<TXT
1. Drag ExeRunner into the Applications folder.
2. The first time, right-click it → Open: macOS does not know this developer.
   If it still refuses: System Settings → Privacy & Security → Open Anyway at the bottom.
3. From there ExeRunner walks you through the steps: Rosetta, launchers.
   $D3DM_EN.
The interface follows the Mac's language (Russian or English); Settings can change it.
TXT
rm -f "$DMG"
# diskutil image on macOS 27 and later, where hdiutil is deprecated; LZFSE opens on macOS 10.11+
if diskutil image create from 2>&1 | grep -q "volumeName"; then
  diskutil image create from --format ULFO --volumeName "ExeRunner" "$STAGE" "$DMG" >/dev/null 2>&1
else
  hdiutil create -volname "ExeRunner" -srcfolder "$STAGE" -format ULFO -ov "$DMG" >/dev/null
fi
echo "built $DMG ($(du -h "$DMG" | cut -f1))"
