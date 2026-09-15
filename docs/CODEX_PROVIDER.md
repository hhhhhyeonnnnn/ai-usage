# Codex local usage provider

## 데이터 경로

`CodexProvider → CodexSessionReader (actor) → CodexUsageParser → UsageSnapshot`

기본 위치는 `~/.codex/sessions/**/*.jsonl` 중 `rollout-`으로 시작하는 파일입니다.
프로세스에 절대 경로인 `CODEX_HOME`이 지정되어 있으면 해당 경로의 `sessions`를 사용합니다.
Finder에서 실행한 앱은 터미널의 환경변수를 자동으로 상속하지 않습니다.
Phase 2의 이번 단계에서는 archive 탐색 / 사용자 지정 폴더 선택 UI를 제공하지 않습니다.

로컬 조사에서 확인한 이벤트:

```json
{
  "timestamp": "2026-09-15T04:00:00.000Z",
  "type": "event_msg",
  "payload": {
    "type": "token_count",
    "rate_limits": {
      "limit_id": "codex",
      "primary": {
        "used_percent": 25,
        "window_minutes": 10080,
        "resets_at": 1789827200
      },
      "secondary": null
    }
  }
}
```

위 숫자는 형식 설명을 위한 예시입니다. JSONL 형식은 현재 로컬 파일에서 관찰한 구조이며
공식적으로 고정된 API 계약으로 가정하지 않습니다. 파싱 변경은 provider 내부에서 처리합니다.

## 해석 규칙

- `used_percent / 100`을 공통 usedFraction으로 변환합니다.
- `primary` / `secondary` 순서에 기간 의미를 부여하지 않습니다.
- `window_minutes == 10080`은 Weekly, 300은 5h, 그 외에는 실제 시간을 표시합니다.
- 전달되지 않은 window를 다른 기록에서 가져오거나 0%로 생성하지 않습니다.
- `limit_id`가 `codex` 또는 없는 legacy 이벤트만 사용합니다. 다른 quota ID는 제외합니다.
- 사용률 누락 / 범위 밖 값은 unknown이며, 기간이 누락되거나 0 이하인 window는 제외합니다.
- `resets_at`은 Unix seconds로 처리하고, 만료되어도 사용률을 0으로 바꾸지 않습니다.
- 가장 최근의 명시적인 빈 windows 기록은 이전 사용량을 대체해 Unavailable을 만듭니다.

공식 [Codex App Server 문서](https://learn.chatgpt.com/docs/app-server#6-rate-limits-chatgpt)는
`account/rateLimits/read`와 rate limit의 사용률·기간·reset seconds 의미를 설명합니다.
현재 구현은 이 RPC를 호출하지 않고 로컬 JSONL의 대응 필드만 읽습니다.

## 최신성 및 계정 범위

이 값은 **마지막 로컬 quota 기록**입니다. 계정의 현재 사용량을 서버에 조회한 결과가 아닙니다.
Codex가 사용량 이벤트를 기록한 뒤 앱에서 Refresh하면 새 값이 반영됩니다.

- **Recorded**: quota 이벤트의 원래 timestamp
- **Checked**: AI Usage가 마지막으로 조회를 완료한 시간
- **Local · stale**: 기록 후 15분 이상 경과 또는 표시된 window의 reset 경과

로그 timestamp가 최신인 기록을 선택하며, 파일 수정 시각으로 quota timestamp를 대신하지 않습니다.
계정을 전환해도 이전 로컬 세션은 남을 수 있습니다. 현재 로그인 계정과 기록의 계정이 같은지
검증하지 않으므로 Settings에서도 이 제약을 안내합니다. API key 사용만으로 quota 이벤트가
기록되지 않는 환경에서는 Unavailable을 표시할 수 있습니다.

## 읽기 비용과 실패 처리

- 수정 시각 기준 최근 **32개 파일**, 파일당 마지막 **2 MiB**만 읽습니다.
- 파일 목록에는 메타데이터만 읽고 내용은 순서대로 처리합니다.
- 같은 파일 크기·수정 시각이면 이전 파싱 결과를 메모리에서 재사용합니다.
- 파일 삭제/잘림/추가 기록은 다음 조회 때 반영합니다.
- JSONL에서 newline까지 완료된 행만 해석하며, 잘린 첫 행·쓰는 중인 마지막 행은 제외합니다.
- 일반 파일만 허용하며 symbolic link 파일, history, auth, config는 읽지 않습니다.
- 읽을 수 없는 한 파일은 건너뛰어 다른 세션을 확인합니다.
- 읽기 가능한 quota가 없으면 Unavailable, 전체 파일 읽기 실패는 안전한 일반 오류로 표시합니다.
- 로그 전체를 탐색하는 보장은 없습니다. quota 이벤트가 탐색 범위보다 오래되었으면
  이전 후보의 기록이나 Unavailable이 표시될 수 있습니다.
- 자동 polling은 없습니다. 메뉴를 열 때 최소 60초 간격으로 확인하며 Refresh는 즉시 조회합니다.

대화 원문은 로그 파일의 바이트 범위에 함께 있을 수 있지만 저장·출력하지 않습니다.
DTO에는 quota 필드만 정의하며, credentials / token totals / 메시지 본문을 보관하지 않습니다.

## 검증

`swift test`로 25개 테스트를 실행합니다. Codex 테스트는 임시 fixture만 사용하며 실제 계정을
읽지 않습니다. Weekly-only, 다른 window 길이, legacy ID, 잘못된 값, 다른 이벤트, stale,
파일 수정 시각과 이벤트 시각의 차이, 쓰는 중인 행, tail 제한, 빈 windows, cache 무효화,
symbolic link 제외, 누락 경로 및 store와 provider의 통합을 검증합니다.

실제 로컬 데이터 연결 확인은 별도 명령입니다:

```sh
python3 scripts/render-previews.py --local
```

quota를 읽지 못하면 실패하고, 성공하면 `build/previews/local-*.png`를 생성합니다.
인증정보나 대화 원문은 출력하지 않습니다. 실제 메뉴바 클릭 검증은 별도로 필요합니다.
