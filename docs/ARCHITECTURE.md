# TalkFlow 폴더 구조와 모듈 설계

문서는 셋으로 나눈다. 섞이면 어느 것이 결정이고 어느 것이 관측인지 알 수 없게 된다.

| 문서 | 담는 것 |
| --- | --- |
| [DESIGN.md](../DESIGN.md) | 제품이 무엇을 하고 왜 그렇게 하는지. 결정과 근거 |
| ARCHITECTURE.md (이 문서) | 모듈 경계, 의존 방향, 파일 관리 기준 |
| [PLATFORM-FINDINGS.md](PLATFORM-FINDINGS.md) | 우리가 통제하지 못하는 것들의 관측된 동작. 확인 방법을 함께 적는다 |
| [AGENTS.md](../AGENTS.md) | 코드를 쓸 때 지킬 규칙 |

실측 기록만 성격이 다르다. 카카오톡·macOS·katok은 우리 통제 밖이라 그 사실들은 언젠가 틀려진다. 동작이 이상해지면 설계를 의심하기 전에 그 문서부터 다시 검증한다.

## 모듈 그래프

```text
TalkFlowApp
 ├─ TalkFlowFeatures
 ├─ TalkFlowApplication
 └─ TalkFlowInfrastructure
      ↓
TalkFlowApplication ──→ TalkFlowDomain ←── TalkFlowInfrastructure
TalkFlowFeatures ────→ TalkFlowApplication, TalkFlowDomain
```

`TalkFlowDomain`은 가장 안쪽 계층이다. 카카오톡의 로컬 DB나 macOS 접근성 API가 바뀌더라도, 도메인 모델과 응답 정책은 유지된다.

## 디렉터리

```text
TalkFlow/
├── AGENTS.md                 # 개발 규칙
├── DESIGN.md                 # 제품·기능 설계
├── Package.swift             # 모듈 의존성 정의
├── docs/
│   ├── ARCHITECTURE.md       # 이 문서 — 모듈 구조와 경계
│   └── PLATFORM-FINDINGS.md  # 카카오톡·macOS·katok 실측 기록
├── scripts/
│   └── install-katok.sh      # katok CLI 설치(체크섬 검증 포함)
├── Sources/
│   ├── TalkFlowApp/          # 앱 시작점, 의존성 조립
│   ├── TalkFlowDomain/       # 모델, 정책, 포트
│   ├── TalkFlowApplication/  # 유스케이스, 작업 흐름
│   ├── TalkFlowInfrastructure/ # 저장소, 카카오·AI·macOS 어댑터
│   └── TalkFlowFeatures/     # SwiftUI 기능 화면
└── Tests/
    ├── TalkFlowDomainTests/         # 정책·프롬프트 단위 테스트
    ├── TalkFlowApplicationTests/    # 파이프라인·전송 큐 (가짜 어댑터)
    └── TalkFlowInfrastructureTests/ # 저장소·아카이브 (합성 fixture)
```

## 책임 분리

| 모듈 | 책임 | 두면 안 되는 것 |
| --- | --- | --- |
| Domain | 계정·채팅방 모델, 응답 정책, 연결 포트 | SwiftUI, SQLite, Keychain, KakaoTalk UI 호출 |
| Application | 계정 확인, 방 동기화, 정책 평가 유스케이스 | 구체 CLI·DB·AI 제공자 생성 |
| Infrastructure | 로컬 저장, Keychain, CLI 실행, macOS 상태, AI 제공자 | 화면 상태와 화면 전용 포맷 |
| Features | 설정, 채팅방 관리, 활동 타임라인, 인사이트 화면 | 카카오톡 DB·접근성 API 직접 호출 |
| App | 의존성 조립과 앱 수명주기 | 도메인 규칙과 기능 구현 |

## 외부 의존성

| 대상 | 용도 | 확보 방법 |
| --- | --- | --- |
| `katok` CLI | 카카오톡 로컬 DB 읽기, 증분 동기화, UI 전송 | `scripts/install-katok.sh` |
| GRDB | TalkFlow 로컬 저장소, katok 아카이브 읽기 | SPM 의존성 |

`katok`은 Homebrew tap을 제공하지 않으므로 릴리스 아카이브를 고정 버전으로 내려받고 게시된 SHA-256을 검증한 뒤 설치한다. `KatokConnection`은 앱 번들, `/opt/homebrew/bin`, `/usr/local/bin` 순으로 실행 파일을 찾는다.

katok의 아카이브(`~/Library/Application Support/katok/archive.sqlite3`)는 katok이 소유하고 TalkFlow는 읽기 전용으로만 접근한다. 이 스키마 결합은 `TalkFlowInfrastructure` 안에 가두고, 나머지 계층은 `KakaoConnection` 포트만 본다.

## 응답 파이프라인

```text
KakaoDatabaseChangeMonitor  (본 DB와 -wal 변경 감지, -shm 제외)
        ↓
KatokRealtimeSyncService    (최소 간격을 두고 katok sync 실행)
        ↓
DraftRepliesForChangedRooms (방 정책 평가 → 후보만 Codex 호출 → 판단 기록)
        ↓
PendingSendStore            (자동 전송 방인 경우에만 대기열 적재)
        ↓
ProcessSendQueue            (주기적으로 SendGate 재검사 → 통과 시 katok send)
```

각 단계는 자기 위층을 모른다. 감지는 정책을 모르고, 정책 판정은 전송을 모르며, 전송은 어떤 모델이 답을 만들었는지 모른다.

이 흐름 밖에서 도는 것이 둘 있고, 둘 다 `SendQueueModel`의 순회에 얹혀 자기 주기로 깨어난다.

```text
SendQueueModel.onPoll (10초마다)
        ├─ OpenConversationsInQuietRooms (1분 주기 · 조용해진 방에 먼저 말 걸기)
        └─ RefreshConversationSummaries  (5분 주기 · 채팅방 요약 증분 갱신)
```

동기화 흐름에 얹지 않는 이유가 서로 다르다. 조용한 방은 정의상 변경을 보고하지 않아 위 파이프라인이 다시 보지 않는다. 요약 갱신은 반대로 **답장 경로에 있어서는 안 되기 때문**이다. 동기화 핸들러는 한 번에 하나씩 끝까지 돌므로, 그 안에 모델 호출을 두면 다음 방의 답장이 그 뒤에 줄을 선다. 답장은 그때 저장돼 있는 요약을 읽기만 한다.

## 상태 소유

- 전역 응답 상태는 `ResponseControlModel` 하나가 소유하고, UI는 이 모델을 통해서만 바꾼다. 값은 저장소에 남아 재실행 후에도 유지된다.
- 화면용 모델은 `TalkFlowModels`가 한 번만 조립해 공유한다. 같은 모델을 두 화면이 각자 만들지 않는다.
- 구체 어댑터 선택은 `TalkFlowComposition` 한 곳에서만 한다. 나머지는 프로토콜 이름만 안다.
- 저장소를 열지 못하면 `UnavailableStore`가 모든 호출에서 실패한다. 기본값을 돌려주면 저장되지 않은 설정이 저장된 것처럼 보인다.

## 파일 관리 기준

- 파일이 250줄에 가까워지면 책임 분리를 먼저 검토한다.
- 400줄을 넘는 소스 파일은 허용하지 않는다.
- 공통 모델을 화면 모듈에 복제하지 말고 Domain으로 올린다.
- 외부 구현은 프로토콜 뒤에 숨기고, UI는 유스케이스를 통해서만 접근한다.
