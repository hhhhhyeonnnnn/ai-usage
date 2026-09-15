# Claude / Antigravity 실제 연결

## 표시

- 기본값은 **Remaining %**. 0.3.0 첫 실행에서 기존 Used 선택도 한 번 전환한다. 이후 설정 변경은 유지한다.
- Claude: 5시간 / 주간 잔여량 = `1 - utilization / 100`. null 또는 잘못된 수치를 0%/100%로 만들지 않는다.
- 2026-09-15 이 Mac의 Claude Free 계정은 인증된 HTTP 200 응답에서 두 한도를 null로 반환했다. 화면에는 Connected와 한도 정보 없음을 표시한다. 모든 Free 계정의 응답이 항상 같다고 가정하지 않는다.
- Antigravity: 서버가 보고한 두 공유 그룹의 **주간** 값을 Compact에 표시한다. Details에서 각 그룹의 주간 / 5시간 값을 모두 확인한다. 모델별 값의 합계나 평균으로 pool을 만들지 않는다.
- reset이 지났더라도 새 값을 추정하지 않고 `Reset due`로 표시한다.

## Claude

`ClaudeDesktopCredentials`가 `~/Library/Application Support/Claude/Cookies`를 SQLite read-only로 열고, `.claude.ai` / `claude.ai`의 `sessionKey`, `lastActiveOrg`만 조회한다. Keychain의 `Claude Safe Storage` 항목으로 Electron v10 쿠키를 메모리에서 복호화한다. DB v24 이상에서는 SHA-256 host prefix를 검증한다. 만료된 쿠키, 다른 도메인, 헤더 문자를 포함한 토큰, UUID가 아닌 조직 ID는 거절한다.

`GET https://claude.ai/api/organizations/{currentOrganization}/usage`로 현재 데스크톱 계정의 한도를 읽는다. 별도 로그인을 생성하거나 OAuth scope를 확대하지 않는다. 데스크톱 앱을 오래 열지 않았다면 앱을 열어 기존 로그인 갱신 후 Retry한다. Keychain 승인 창이 나타나면 AI Usage의 Claude 인증 읽기 요청인지 확인하고 허용할 수 있다.

쿠키의 Chromium 저장 형식 참고: [Chromium cookie store](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/net/extras/sqlite/sqlite_persistent_cookie_store.cc).
사용량 endpoint 참고 및 교차 확인: [CodexBar의 Claude provider 문서](https://github.com/steipete/CodexBar/blob/main/docs/claude.md). 이 프로젝트 구현은 이 Mac의 실제 응답과 합성 테스트로 검증했다.

## Antigravity

실행 중인 **Antigravity Hub**의 language server를 찾아 `RetrieveUserQuotaSummary` RPC를 호출한다. 같은 UID, `/Applications/Antigravity.app/Contents/` 아래 language_server 실행 파일을 별도로 확인하고, 그 PID가 실제 LISTEN 중인 `127.0.0.1` 포트만 사용한다. CSRF 토큰은 프로세스 인자에서 메모리로 읽는다. 다른 앱 프로세스, 외부 주소, 전체 포트 스캔은 사용하지 않는다. 로컬 HTTP 포트를 사용하므로 HTTPS 인증서 검증을 끄지 않는다.

실제 응답 구조:

```text
response.groups[]
  displayName: Gemini Models | Claude and GPT models
  buckets[]
    window: weekly | 5h
    remainingFraction: 0...1
    resetTime: RFC3339
```

`GetUserStatus`의 모델별 `quotaInfo`는 Gemini가 100%이면서 실제 weekly pool은 66%인 사례가 확인되었다. 따라서 해당 값으로 공유 pool을 대체하지 않는다. 현재 상세 화면은 실제 공유 pool의 기간별 한도를 표시한다. 모델 활동 추적은 추가하지 않았다.

## 네트워크 / 제한

- 독립 actor provider, 30초 메모리 캐시, 429일 때 3분 재시도 제한.
- 메뉴 열기(최소 60초 간격)와 수동 갱신. 백그라운드 polling 없음.
- Ephemeral URLSession, 쿠키 저장소/credential 저장소/cache 미사용, 리다이렉트 차단, 응답 최대 2MB, 요청/전체 응답 timeout.
- API에 필요한 인증 정보만 지정된 서비스로 전달. 로그, UserDefaults, 파일에 토큰이나 원본 응답을 기록하지 않는다.
- 연결 실패 시 고정된 안내 문구를 표시한다. 성공한 다른 provider는 계속 표시한다. production에서 demo로 대체하지 않는다.
- Claude와 Antigravity의 앱 내부 endpoint라 upstream 변경 시 parser 업데이트가 필요하다. 현재 Antigravity 구형 IDE의 별도 저장소나 다른 설치 경로는 지원하지 않는다.
- Keychain/프로세스 접근이 필요하므로 현재 로컬 배포는 App Sandbox 미사용이며, ad hoc 서명이다.

## 검증

`swift test`는 네트워크나 실제 인증 정보를 사용하지 않는다. Claude null/잘못된 한도, Antigravity 중복/알 수 없는 그룹, 주간 누락, OpenSSL로 생성한 합성 쿠키 복호화와 도메인 불일치, HTTP redirect 거절, 표시 설정 이전을 검증한다.

`python3 scripts/render-previews.py --local`은 세 provider가 모두 실제 snapshot을 반환하는지 검사한 후 SwiftUI Compact/Details × Light/Dark 이미지를 만든다. 출력에는 한도 수치와 source만 포함하며 인증 정보는 포함하지 않는다.
