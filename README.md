# AI Usage

macOS 메뉴바에서 AI 서비스 사용량을 확인하는 SwiftUI 앱입니다.
**v0.3.1: Codex, Claude, Antigravity 실제 연결. 기본 표시는 남은 사용량입니다.**
Codex는 로컬 세션 기록, Claude는 데스크톱 로그인, Antigravity는 실행 중인 로컬 서버를 사용합니다.
Claude Free 계정처럼 한도 API가 빈 값을 반환하면 연결 상태와 `한도 정보 없음`을 표시합니다.
[Claude / Antigravity 연결 문서](docs/CONNECTED_PROVIDERS.md)에서 데이터 범위와 인증 방식을 확인할 수 있습니다.
자세한 데이터 범위와 제약은 [Codex provider 문서](docs/CODEX_PROVIDER.md)에 정리했습니다.

## 실행

- macOS 14 이상, Xcode 16 이상 / Swift 6
- 외부 패키지 의존성 없음
- `AIUsage.xcodeproj`를 열고 **AIUsage** scheme에서 Run (`⌘R`)
- 메뉴바의 **AI** 글자를 클릭합니다. Dock 아이콘은 표시하지 않습니다.

터미널에서 앱 번들 빌드:

```sh
zsh scripts/build-app.sh
open "build/AI Usage.app"
```

Swift Package로도 빌드와 테스트가 가능합니다:

```sh
swift build
swift test
```

Xcode 프로젝트는 앱 실행용이며 테스트는 `swift test`로 실행합니다.
빌드는 로컬 실행을 위한 ad hoc 서명을 사용합니다. 배포용 서명·공증은 포함하지 않습니다.
`build-app.sh`는 Swift Package 빌드 결과를 `.app`으로 묶으므로 Xcode IDE 없이도 실행 가능합니다.

이 환경에서는 Xcode의 CoreSimulator 프레임워크 누락으로 `xcodebuild`가 시작 단계에서
실패했습니다. Swift Package 빌드와 테스트는 정상 작동하며, Xcode 프로젝트 빌드는
Xcode 설치 복구 후 별도로 확인해야 합니다.

## 구현 범위

- `MenuBarExtra(.window)` 기반 320 × 371pt Compact UI
- 서비스 이름 왼쪽 / 사용량 링 오른쪽의 가로 행 배치
- Compact 40pt / 상세 52pt Usage Ring, 12시 시작, % / quota 이름 / reset 표시
- Codex 실제 로컬 quota / reset / 기록 시각, 누락된 기간은 추정하지 않음
- Claude 데스크톱 계정의 실제 5시간 / 주간 한도; API가 미제공하면 수치 없음
- Antigravity의 실제 Gemini / Claude·GPT 주간 pool을 Compact에 표시
- Antigravity Details에서 pool별 주간 / 5시간 한도와 reset 확인; 모델 수치로 합산하지 않음
- 시스템 Light / Dark 기본 지원, Settings에서 System / Light / Dark 선택
- Remaining 기본값, 기존 Used 설정도 이번 업데이트에서 한 번 전환; 이후 선택은 UserDefaults에 저장
- 메뉴를 열 때 갱신(최소 60초 간격) / 수동 Refresh (`⌘R`), provider별 실패 상태와 Retry
- Settings (`⌘,`), Quit (`⌘Q`), 작은 화면에서도 고정된 footer
- provider별 Local record / Connected / Live 표시, Codex 기록은 15분 경과 또는 reset 경과 시 stale 표시

Launch at Login은 Phase 3 예정임을 표시한 비활성 control입니다.
자동 provider polling은 없으며 화면의 시간 문구만 60초 주기로 갱신합니다.
Mock provider는 테스트와 데모 렌더링에만 사용합니다.
Codex의 Recorded 시각은 원본 이벤트 시각입니다. 하단 Checked는 앱의 마지막 조회 시각입니다.

## 구조

```text
AIUsage/
├── App/         앱 진입점, @MainActor @Observable UsageStore, 표시 설정
├── Models/      ProviderType, UsageSnapshot, UsageBucket, ProviderState
├── Providers/   Codex / Claude / Antigravity provider, parser, 인증 및 HTTP, MockUsageProvider
├── Services/    actor UsageService — 동시 fetch, 개별 결과 전달
├── Views/       메뉴, 링, provider, Antigravity 상세, Settings
├── Utilities/   percentage / reset / updated 문구
└── Resources/   Info.plist (LSUIElement)
Tests/AIUsageTests/
```

`UsageProvider → UsageService → UsageStore → SwiftUI` 흐름입니다.
UI는 공통 snapshot만 사용하고 파일/응답 parsing은 하지 않습니다.
provider 값과 fetch 결과는 `Sendable`, 서비스는 actor, 화면 상태는 MainActor로 격리합니다.
Swift 6 complete concurrency checking을 사용하며 `@unchecked Sendable` 우회는 없습니다.

알 수 없는 사용량은 `—`로 표시하고 0%로 처리하지 않습니다.
pool의 수치는 children과 독립적이며 모델 합계로 추정하지 않습니다.
Codex의 `sessions/rollout-*.jsonl`을 읽고 quota 이벤트만 공통 모델로 변환합니다.
Claude 로그인 정보는 Claude 전용 Cookies DB와 Keychain에서 메모리로 읽습니다. Claude API는 HTTPS,
Antigravity RPC는 검증된 앱 프로세스의 loopback HTTP 포트에만 요청합니다. 인증 정보와 응답은 디스크에 저장하지 않습니다.
원본 오류가 노출되지 않도록 서비스에서는 고정된 안전한 오류 문구만 전달합니다.

## 디자인

- [Compact Figma](https://www.figma.com/design/Uqvbh72hHWUknX6nJK3vQe?node-id=1-18)
- [Antigravity 상세 Figma](https://www.figma.com/design/Uqvbh72hHWUknX6nJK3vQe?node-id=1-73)

초안의 링 구성을 참고하고, 사용자 피드백에 따라 이름과 링을 가로로 배치했습니다. 잘리던 reset/설명 문구는
SwiftUI의 자연스러운 높이로 표시하고, 배경·텍스트·구분선은 semantic color/material을 사용합니다.
상세는 Compact와 같은 320 × 371pt 창 안에서 기간별 한도만 표시하며, 상단 뒤로 버튼으로 복귀합니다.
화면 전환 시 창 높이가 커지지 않아 MenuBarExtra의 기존 창 경계에서 상세/하단 버튼이 잘리지 않습니다.
내용이 길어지면 provider 영역만 스크롤합니다.
상세 한도 행은 남은 비율과 reset을 텍스트로 표시합니다.

API 참고: [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra),
[Settings](https://developer.apple.com/documentation/swiftui/settings).

실제 SwiftUI 뷰의 Light/Dark 렌더링:

```sh
python3 scripts/render-previews.py
# 세 provider 실제 연결 및 화면 확인 (Claude 로그인 / Antigravity 실행 필요)
python3 scripts/render-previews.py --local
```

이미지는 `build/previews/`에 생성됩니다. 시스템 화면 모드를 변경하지 않습니다.
이 렌더링은 정적 레이아웃 확인용이며 실제 메뉴바 클릭 / Settings 창 열기 / Quit 검증을 대체하지 않습니다.

### 검증 결과

- Swift 6 빌드 및 테스트 36개 통과 (응답 파싱, 합계 추정 방지, 쿠키 도메인 검증, 리다이렉트 차단, 설정 이전 포함)
- Codex 실제 로컬 기록, Claude 실제 API 200 응답 및 null 한도, Antigravity 실제 공유 pool 응답 확인
- Compact / Antigravity 상세 × Light / Dark, 4개 렌더링 확인
- `.app` 번들 생성 및 로컬 ad hoc 서명 검증 완료
- Xcode 프로젝트 plist / scheme XML / 소스 포함 검사 통과
- 이전 버전에서 사용자가 AI 메뉴바 표시 및 클릭 열림을 확인함; 새 버전은 실제 연결 렌더링으로 검증
- Xcode 빌드는 앞서 기재한 설치 환경 문제로 미검증

## 다음 단계

Phase 3: Launch at Login, 저빈도 refresh scheduler/file watcher, history, 앱 아이콘 및 배포 준비.
