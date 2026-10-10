#!/bin/bash
# Packs build/app.noindex/ExeRunner.app (with its engine inside; scripts/build-engine.sh portable, then
# build-app.sh) into build/ExeRunner-<version>.dmg to hand to friends: the app and a link to
# /Applications to drag it onto. D3DMetal is not in it; each user imports Apple's download.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/app.noindex/ExeRunner.app"
[ -f "$APP/Contents/Resources/engine/engine.json" ] || { echo "no engine inside $APP: run build-engine.sh portable, then build-app.sh"; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$ROOT/build/ExeRunner-$VERSION.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

ditto "$APP" "$STAGE/ExeRunner.app"
ln -s /Applications "$STAGE/Applications"
if [ -d "$APP/Contents/Resources/d3dmetal" ]; then
  D3DM="D3DMetal от Apple уже внутри; новую версию можно подключить из Game Porting Toolkit"
else
  D3DM="D3DMetal: скачай Game Porting Toolkit на developer.apple.com (вход по Apple ID, бесплатно)
   и перетащи .dmg в окно ExeRunner"
fi
cat > "$STAGE/Как открыть.txt" <<TXT
1. Перетащи ExeRunner в папку «Программы» (Applications).
2. Первый раз открой его правой кнопкой мыши → «Открыть»: macOS не знает этого разработчика.
   Если она всё равно не даёт: «Системные настройки» → «Конфиденциальность и безопасность» →
   внизу «Всё равно открыть».
3. Дальше ExeRunner сам проведёт по шагам: Rosetta, лаунчеры.
   $D3DM.
TXT
rm -f "$DMG"
# diskutil image on macOS 27 and later, where hdiutil is deprecated; LZFSE opens on macOS 10.11+
if diskutil image create from 2>&1 | grep -q "volumeName"; then
  diskutil image create from --format ULFO --volumeName "ExeRunner" "$STAGE" "$DMG" >/dev/null 2>&1
else
  hdiutil create -volname "ExeRunner" -srcfolder "$STAGE" -format ULFO -ov "$DMG" >/dev/null
fi
echo "built $DMG ($(du -h "$DMG" | cut -f1))"
