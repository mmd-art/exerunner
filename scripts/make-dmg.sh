#!/bin/bash
# Packs build/app.noindex/WinRunner.app (with its engine inside; scripts/build-engine.sh portable, then
# build-app.sh) into build/WinRunner-<version>.dmg to hand to friends: the app and a link to
# /Applications to drag it onto. D3DMetal is not in it; each user imports Apple's download.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/app.noindex/WinRunner.app"
[ -f "$APP/Contents/Resources/engine/engine.json" ] || { echo "no engine inside $APP: run build-engine.sh portable, then build-app.sh"; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$ROOT/build/WinRunner-$VERSION.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

ditto "$APP" "$STAGE/WinRunner.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/Как открыть.txt" <<'TXT'
1. Перетащи WinRunner в папку «Программы» (Applications).
2. Первый раз открой его правой кнопкой мыши → «Открыть»: macOS не знает этого разработчика.
   Если она всё равно не даёт: «Системные настройки» → «Конфиденциальность и безопасность» →
   внизу «Всё равно открыть».
3. Дальше WinRunner сам проведёт по шагам: Rosetta, D3DMetal с сайта Apple, лаунчеры.
TXT
rm -f "$DMG"
# diskutil image on macOS 27 and later, where hdiutil is deprecated; LZFSE opens on macOS 10.11+
if diskutil image create from 2>&1 | grep -q "volumeName"; then
  diskutil image create from --format ULFO --volumeName "WinRunner" "$STAGE" "$DMG" >/dev/null 2>&1
else
  hdiutil create -volname "WinRunner" -srcfolder "$STAGE" -format ULFO -ov "$DMG" >/dev/null
fi
echo "built $DMG ($(du -h "$DMG" | cut -f1))"
