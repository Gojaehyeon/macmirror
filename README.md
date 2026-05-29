# macmirror

아이폰 / 아이패드를 맥의 무선 보조 모니터로 쓰는 도구입니다. 디스플레이 사이즈는 자유.

맥에 원하는 비율의 가상 디스플레이를 만들고, 그 화면을 30fps 로 캡처해서 아이폰 앱에 HTTP 로 송출합니다. iPhone Pro Max / iPad Pro / 1:1 / 16:9 등 프리셋, 또는 사용자 정의 W×H.

```
┌────────────── macmirror.app (Mac) ──────────────┐         ┌─── macmirror (iOS) ───┐
│  ① 가상 디스플레이 생성  (원하는 비율 자유 선택)    │         │   /frame 폴링         │
│        ↓                                         │   WiFi  │     ↓                 │
│  ② ScreenCaptureKit 캡처 (GPU JPEG)              │  ─────► │   UIImage 디코드      │
│        ↓                                         │         │   풀스크린 렌더       │
│  ③ HTTP /frame 엔드포인트                         │         │                       │
└──────────────────────────────────────────────────┘         └───────────────────────┘
```

## 특징

- **사파리 안전영역 반영 프리셋** — Dynamic Island·홈 인디케이터·툴바 제외한 실제 가용 viewport 기준
- **가로/세로 토글** — 메뉴바에서 즉시 회전, 모든 프리셋과 사용자 정의에 적용
- **사용자 정의 W×H** — 200~8192px 사이 임의 사이즈
- **메뉴바 앱** — Dock 아이콘 없음, 항상 떠 있음
- **HTTP 폴링** — WebSocket 의존 없음, 어떤 iOS 환경에서도 동작
- **Cloudflare 터널** — 셀룰러나 외부망에서 접속 가능 (선택)
- **워치 호환** — [watchmac](https://github.com/Gojaehyeon/watchmac) 과 같은 `/frame` 엔드포인트

## 요구 사항

- macOS 14 이상 (Apple Silicon 권장)
- Xcode 16 이상 (iOS 앱 빌드용)
- 화면 기록 권한 (시스템 설정 → 개인정보 보호 및 보안 → 화면 기록)
- (선택) `cloudflared` — 공개 터널 쓸 때만. `brew install cloudflared`

## 설치 — 맥 메뉴바 앱

```bash
cd mac
./build-app.sh
open macmirror.app
```

메뉴바 → 📱 macmirror 아이콘 → 디스플레이 사이즈에서 프리셋 또는 "사용자 정의…" 선택.

## 설치 — iOS 앱

```bash
cd ios
xcodegen generate
open MacMirror.xcodeproj
```

Xcode에서:
1. TARGETS → MacMirror → Signing & Capabilities → 본인 Apple ID 선택
2. 디바이스 셀렉터에서 본인 아이폰 또는 시뮬레이터 선택 → ▶ Run
3. 앱에서 가운데 탭 → 맥 메뉴바의 LAN 주소 입력 → 연결

> 무료 Apple ID 서명은 7일마다 재서명 필요.

## CLI 옵션

```bash
./mac/.build/release/macmirror \
  --preset "iPhone Pro Max" \
  --fps 30 \
  --quality 0.65 \
  --port 8890
```

| 플래그 | 효과 |
|---|---|
| `--preset <name>` | 위 프리셋 이름으로 사이즈 설정 |
| `--width / --height` | 직접 픽셀 지정 |
| `--fps` | 캡처 FPS (기본 30) |
| `--quality` | JPEG 품질 0.0~1.0 (기본 0.65) |
| `--port` | 서버 포트 (기본 8890) |
| `--source main` | 가상 디스플레이 대신 주 화면 미러링 |

## 디렉토리 구조

```
macmirror/
├── mac/                    # macOS 메뉴바 앱 (SPM)
│   ├── Package.swift
│   ├── build-app.sh
│   └── Sources/
│       ├── CVirtualDisplay/   # 비공개 CGVirtualDisplay 브리지
│       └── macmirror/         # Swift 앱 본체
└── ios/                    # iOS 앱 (Xcode + xcodegen)
    ├── project.yml
    └── App/
        ├── App.swift
        ├── ContentView.swift
        └── MirrorStream.swift
```

## 한계 / 주의

- `CGVirtualDisplay` 는 **비공개 API** 입니다. macOS 메이저 업데이트로 깨질 수 있습니다.
- macOS 26.5 에서 너무 작은 가상 디스플레이는 System Settings → Displays UI 에서 숨겨질 수 있음. 프리셋은 모두 UI 노출되는 크기로 잡혀 있음.
- 무료 Apple ID 서명은 7일마다 재서명 필요.

## 라이선스

MIT
