#!/bin/bash
# macmirror.dmg 만들기 — build-app.sh 로 앱을 빌드한 뒤 드래그-설치용 DMG 로 패키징.
set -e
cd "$(dirname "$0")"

APP="macmirror.app"
DMG="macmirror.dmg"
VOL="macmirror"
STAGE="$(mktemp -d)"

echo "① 앱 빌드…"
./build-app.sh >/dev/null

echo "② DMG 스테이징…"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "③ DMG 생성…"
rm -f "$DMG"
hdiutil create \
  -volname "$VOL" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG" >/dev/null

rm -rf "$STAGE"

SIZE=$(du -h "$DMG" | cut -f1)
echo "④ 완료 → $(pwd)/$DMG  ($SIZE)"
echo
echo "   드래그해서 Applications 폴더에 넣으면 설치됩니다."
echo "   (서명 안 된 앱이라 첫 실행은 우클릭 → 열기)"
