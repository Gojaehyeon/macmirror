#!/bin/bash
# macmirror.dmg 만들기 — 앱 빌드(+Developer ID 서명) → DMG 패키징 → 공증 → staple.
# notary 프로필이 등록돼 있으면 자동 공증, 없으면 서명만 된 DMG 까지만.
set -e
cd "$(dirname "$0")"

APP="macmirror.app"
DMG="macmirror.dmg"
VOL="macmirror"
SIGN_ID="${MACMIRROR_SIGN_ID:-Developer ID Application: Jahyeon Ko (RP5GZ99V95)}"
NOTARY_PROFILE="${MACMIRROR_NOTARY_PROFILE:-macmirror}"
STAGE="$(mktemp -d)"

echo "① 앱 빌드 + 서명…"
./build-app.sh >/dev/null

echo "② DMG 스테이징…"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "③ DMG 생성…"
rm -f "$DMG"
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

# DMG 자체도 서명 (배포 무결성).
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_ID"; then
    echo "④ DMG 서명…"
    codesign --force --sign "$SIGN_ID" "$DMG"
fi

# 공증 — notary 프로필 있을 때만.
if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "⑤ 공증 제출 중… (Apple 서버 왕복, 보통 1~5분)"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    echo "⑥ staple…"
    xcrun stapler staple "$DMG"
    echo "   검증:"
    spctl -a -t open --context context:primary-signature -v "$DMG" 2>&1 | tail -2 || true
else
    echo "⑤ notary 프로필 '$NOTARY_PROFILE' 없음 → 공증 생략 (서명만 됨)"
    echo "   공증하려면: xcrun notarytool store-credentials $NOTARY_PROFILE ..."
fi

SIZE=$(du -h "$DMG" | cut -f1)
echo "⑦ 완료 → $(pwd)/$DMG  ($SIZE)"
