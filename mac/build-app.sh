#!/bin/bash
# macmirror.app 만들기 — 메뉴바 앱.
# Developer ID 인증서가 있으면 hardened runtime 으로 정식 서명, 없으면 ad-hoc.
set -e
cd "$(dirname "$0")"

# 서명 ID — 환경변수로 덮어쓸 수 있음. 기본은 보유한 Developer ID.
SIGN_ID="${MACMIRROR_SIGN_ID:-Developer ID Application: Jahyeon Ko (RP5GZ99V95)}"

echo "① 빌드 중…"
swift build -c release

BIN=".build/release/macmirror"
APP="macmirror.app"

echo "② 앱 패키징 중…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/macmirror"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                <string>macmirror</string>
    <key>CFBundleDisplayName</key>         <string>macmirror</string>
    <key>CFBundleIdentifier</key>          <string>com.macmirror.menubar</string>
    <key>CFBundleExecutable</key>          <string>macmirror</string>
    <key>CFBundleVersion</key>             <string>1.0</string>
    <key>CFBundleShortVersionString</key>  <string>1.0</string>
    <key>CFBundlePackageType</key>         <string>APPL</string>
    <key>LSUIElement</key>                 <true/>
    <key>LSMinimumSystemVersion</key>      <string>14.0</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>아이폰/아이패드에 맥 화면을 표시하기 위해 화면을 캡처합니다.</string>
</dict>
</plist>
PLIST

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_ID"; then
    echo "③ Developer ID 서명 (hardened runtime)…"
    codesign --force --options runtime --timestamp \
        --sign "$SIGN_ID" "$APP"
    echo "   서명 검증:"
    codesign --verify --strict --verbose=2 "$APP" 2>&1 | tail -2
else
    echo "③ Developer ID 인증서 없음 → ad-hoc 서명 (배포 불가, 로컬 실행용)"
    codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
fi

echo "④ 완료 → $(pwd)/$APP"
