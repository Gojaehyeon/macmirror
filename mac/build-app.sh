#!/bin/bash
# macmirror.app 만들기 — 메뉴바 앱.
set -e
cd "$(dirname "$0")"

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

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "③ 완료 → $(pwd)/$APP"
echo "   더블클릭하거나 'open $APP' 으로 실행하세요."
