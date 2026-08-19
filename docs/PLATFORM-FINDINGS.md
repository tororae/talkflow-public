# 플랫폼 실측 기록

TalkFlow는 우리가 만들지 않은 소프트웨어 세 개에 얹혀 있다. 카카오톡, macOS, 그리고 연결 도구인 katok이다. 이 문서는 그 셋을 실제로 측정해서 알아낸 사실만 모은다.

설계 결정은 [DESIGN.md](../DESIGN.md)에, 모듈 구조는 [ARCHITECTURE.md](ARCHITECTURE.md)에 있다. 여기에는 **관측된 동작**만 둔다. 셋 다 우리 통제 밖이라 이 사실들은 언젠가 틀려진다. 그래서 각 항목에 확인 방법을 함께 적는다. 동작이 이상해지면 설계를 의심하기 전에 이 문서를 다시 검증하라.

측정 환경: MacBook Pro (M1 Pro, 외장 모니터 없음) · macOS 26 · 카카오톡 macOS · katok 0.3.0 · 2026-08-08

---

## 1. 계정과 데이터베이스

### 1.1 카카오톡은 계정마다 데이터베이스를 따로 만든다

로그아웃하고 다른 계정으로 로그인하면 새 파일이 생기고 **이전 파일은 그대로 남는다.** 두 파일 모두 `~/Library/Containers/com.kakao.KakaoTalkMac/Data/Library/Application Support/com.kakao.KakaoTalkMac/`에 있고, 이름은 78자리 소문자 16진수다.

파일 이름과 SQLCipher 키가 **모두** `(user_id, 기기 uuid)`에서 PBKDF2-HMAC-SHA256 10만 회로 유도된다. 구현은 `KakaoKeyDerivation`에 있고, 실제 기기에서 관측한 파일명을 오라클로 고정 테스트한다.

확인: 컨테이너에서 78자리 16진수 파일을 세어 본다. 둘 이상이면 이 기기에서 계정을 바꾼 적이 있다.

### 1.2 연결 도구는 캐시된 계정을 계속 읽는다

katok과 kakaocli 모두 캐시된 `user_id`로 파일 이름을 유도하고 그 파일만 읽는다. 계정을 바꿔도 캐시가 그대로면 **로그아웃한 계정의 대화를 계속 읽는다.** katok의 `[PATH]` 인자는 `--source macos`에서 무시되므로 파일을 지정할 수도 없다.

실제로 9일간 이 상태였고, 그동안 동기화는 매번 "성공, 신규 0건"을 보고했다. 조용한 계정처럼 보였지 고장으로 보이지 않았다.

위험한 쪽은 읽기가 아니다. **전송은 UI 자동화라 현재 로그인된 계정으로 나간다.** 옛 계정 대화로 만든 답장이 새 계정 이름으로 나갈 수 있다.

확인: `katok source chats --source macos --json`의 방 개수를 카카오톡 화면의 실제 방 개수와 대조한다.

### 1.3 현재 계정의 user_id는 어디에도 안 남아 있을 수 있다

정상 경로는 카카오톡이 설정 파일 키 이름에 값을 박아 두는 것이다(`FSChatWindowTransparency<user_id>` 등에서 공통 접미사를 뽑는다). 그런데 이 키는 채팅창을 열고 조작해야 생긴다. 갓 전환한 계정에는 없다. 이 기기에서는 `FSChatWindow*` 키가 0개였고, kakaocli는 `User ID: NOT FOUND`를 냈다.

폴백은 설정 파일에 남은 `sha512(user_id)` 해시를 역산하는 것이다. katok도 같은 기법을 쓰지만 `0..10억`만 훑어서 이 기기의 값(9자리)을 못 찾았다. 100억까지 넓히면 찾는다. M1 Pro에서 초당 약 2,600만 개, 100억까지 약 3분 30초.

찾은 값은 `KakaoAccountStore`에 저장하고 `KATOK_KAKAO_USER_ID`로 katok에 넘긴다.

확인: `KakaoAccountResolver.resolves(userID:)`가 true인지 본다. 저장된 값이 살아 있는 파일을 유도하지 못하면 계정이 바뀐 것이다.

### 1.4 아카이브에는 여러 계정이 함께 쌓인다

**이 항목은 코드보다 사람을 더 자주 속인다.** 2026-08-11에 이 저장소의 설계 논의 전체가 이 필터를 빠뜨린 숫자 위에서 진행됐다. 측정한 계정은 방 11개·사람 350명·메시지 14,654건인데, 필터 없이 세면 방 245개·사람 4,627명·메시지 435,155건이 나온다 — **97%가 읽지도 않는 계정 것이다.** 규모를 재는 모든 질의에 `account_hash`를 건다.

katok의 아카이브(`archive.sqlite3`)는 동기화한 모든 계정을 한 파일에 담는다. `messages`에는 `account_hash` 컬럼이 있지만 **`chats` 테이블에는 계정 컬럼이 없다.**

`chats`에서 방 목록을 읽으면 계정이 섞인다. 실측에서 로그아웃한 계정 234개와 읽고 있는 계정 3개가 함께 나왔다. 그래서 방 목록도 `messages`에서 뽑는다.

`account_hash`는 `sha256(user_id)`다. 유도할 수는 있지만, 코드는 "이 사용자가 보낸 메시지가 속한 계정"으로 조회한다(`KatokArchiveReader`).

---

## 2. 세션 잠금과 전송

### 2.1 전송을 막는 것은 오직 세션 잠금이다

디스플레이도, 노트북 뚜껑도 아니다.

| 조건 | 결과 |
| --- | --- |
| 화면 켬, 카카오톡이 앞 | 전송 성공 |
| 화면 켬, 다른 앱이 앞 | 전송 성공. 연결 도구가 카카오톡을 앞으로 가져온다 |
| **뚜껑 닫힘, 세션 안 잠김** | **포커스를 즉시 뺏을 때만 성공.** 3.4 참고 |
| 세션 잠김 | 거부. 잠금 화면이 앞을 차지해 입력할 대상이 없다 |
| 세션 잠김 → 깨움 → 전송 | 성공(암호 유예 안) |

잠금 화면이 앞에 있으면 연결 도구는 엉뚱한 앱에 타이핑하지 않으려고 거부한다. 이때 반환되는 실패는 "아무것도 보내지 않았으니 재시도하라"이며, **재시도 가능한 실패로 취급해야 한다.**

### 2.2 디스플레이가 자면 1초 안에 잠긴다

`screenLock delay`가 300초여도 마찬가지다. 그 값은 **암호를 묻기 시작하는 시점**일 뿐, 잠금 화면 자체는 즉시 올라온다. 유예 안에서는 `IOPMAssertionDeclareUserActivity`로 깨우면 잠금이 풀린다. 유예가 지나면 깨워도 풀리지 않는다.

확인: `CGSessionCopyCurrentDictionary()["CGSSessionScreenIsLocked"]`를 `pmset displaysleepnow` 전후로 재 본다.

### 2.3 뚜껑 상태는 `AppleClamshellState`로만 읽는다

`CGDisplayIsAsleep`도, 활성 디스플레이 개수도 뚜껑 지표가 아니다. 뚜껑이 열려도 닫혀도 같은 값이 나온다. 이 문서를 만드는 과정에서 두 번 이 착각으로 결론을 잘못 냈다.

```
ioreg -r -k AppleClamshellState -d 4 | grep AppleClamshellState
```

### 2.4 뚜껑을 닫아도 맥은 자지 않을 수 있다

이 기기의 `sleep` 설정은 1분인데도 자지 않았다. 다른 앱이 `NoIdleSleep` 어서션을 잡고 있었기 때문이다. 뚜껑 닫힌 채 5분간 연속 동작을 기록했고 전체 로그에서 `Entering Sleep`은 0회였다.

그래서 TalkFlow는 자동 응답이 켜진 동안 스스로 어서션을 잡는다(`MacWakefulnessController`). 다른 앱에 의존하지 않기 위해서다.

---

## 3. 접근성(AX)과 Space

### 3.1 AX는 현재 활성 Space의 창만 본다

전체화면 앱을 쓰는 동안에는 다른 데스크탑에 있는 카카오톡 창을 **존재조차 알 수 없다.** 전송 로직의 문제가 아니라 타이핑할 대상을 못 찾는 것이다.

```
Claude 전체화면:  AXWindows = 0
데스크톱 Space:   AXWindows = 2   제목=["hangyeol", "카카오톡"]
Claude 복귀:      AXWindows = 0
```

Dock의 "할당 → 모든 데스크탑"으로 우회하려 했으나, 데스크톱이 하나뿐이면 그 메뉴 항목 자체가 나타나지 않는다.

### 3.2 잠긴 세션에서는 창 트리가 스텁으로 바뀐다

`AXWindows` 호출은 성공(코드 0)하고 원소도 2개 반환하지만, 그 원소들의 role이 `AXWindow`가 아니라 `AXApplication`이고 자식이 4개뿐이다. 성공 코드와 개수만 보면 살아 있는 것처럼 보인다. **role까지 확인해야 한다.**

### 3.3 AX 직접 조작은 포커스를 뺏지 않는다

입력란의 `AXValue`를 설정하고 그 창의 전송 버튼을 `AXPress`하면 앞선 앱이 무엇이든 전송된다. 실측에서 Finder가, 나중에는 Claude가 계속 앞에 있었다.

katok이 카카오톡을 앞으로 가져오는 이유는 **전역 CGEvent**를 쓰기 때문이다. 전역 키 이벤트는 앞선 앱에 꽂히므로 대상이 앞에 있어야 한다.

조건: 그 방의 창이 이미 열려 있어야 하고, 같은 Space여야 한다(3.1). 대화방 창의 입력란은 창 하단의 `AXTextArea` 중 `AXValue`가 설정 가능한 것이다. 메시지 말풍선도 같은 role이지만 설정 불가라 구분된다.

### 3.3.1 `postToPid`로 보낸 키 이벤트는 창이 아니라 **앱**에 간다

**이 문서에 오래 적혀 있던 "pid로 Return을 보내면 전송된다"는 반쪽만 맞았다.** 키 이벤트는 앱을 지목하고, 카카오톡은 그것을 자기 key window에 준다. 그 창이 보내려던 방이 아니면 Return은 **다른 방 입력란에** 떨어진다. 입력란에 `kAXFocused`를 세워도 앱의 key window는 움직이지 않는다.

2026-08-10 실측, 창 9개를 열어 둔 상태:

```
앱의 AXFocusedWindow   늦반딧불 등산모임
보내려던 창            강민석, …            (AXMain=false)
```

그 안드로이드 방으로 가는 전송은 전부 성공하고 강민석 방은 전부 실패했다. 증상은 **글자가 써졌다 지워지고 「대화창이 닫혀 있어」로 기록**되는 것이었다(입력란이 안 비니 실패 처리 후 지움 → katok 폴백 → katok도 실패).

안 나가는 것보다 나쁜 쪽은 Return이 사라지지 않는다는 점이다. 다른 방 입력란에 사용자가 쓰다 만 문장이 있었으면 그게 사용자 이름으로 나갔을 것이다.

확인: `AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute)`의 제목을 보내려는 방과 대조한다.

### 3.3.2 입력란 값은 대입 즉시 카카오톡에 반영되지 않는다

`AXValue`를 설정하면 **읽기는 바로 되지만** 카카오톡 내부 모델은 약 0.3초 뒤에 안다. 판정 기준은 전송 버튼의 `AXEnabled`다.

```
대입 직후    입력란="테스트"  전송 enabled=false
100ms       입력란="테스트"  전송 enabled=false
300ms       입력란="테스트"  전송 enabled=true
```

예전 코드는 대입 60ms 뒤에 Return을 보냈다. 빈 버퍼에 커밋한 것이다. 고정 대기 대신 **버튼이 켜질 때까지 기다리는 것**이 옳다. 그것이 카카오톡 자신의 "받았다"는 신호다.

### 3.3.3 `AXPress`는 성공해도 `kAXErrorFailure`를 돌려준다

대화방 창의 `전송` 버튼(`AXButton`, title=`전송`, 창의 직속 자식)을 누르면 **-25200을 반환하면서 실제로는 전송된다.** key window가 아닌 방에서 눌러 -25200을 받고 1초 뒤 아카이브에서 그 메시지를 찾아 확인했다.

**이 반환값을 `guard`로 믿으면 성공한 전송이 전부 재시도 가능한 실패가 되고, 같은 말이 katok으로 한 번 더 나간다.** 누름의 반환값은 어느 쪽으로도 증거가 아니다. 영수증은 입력란이 비는 것뿐이다.

### 3.3.4 `AXMain`은 key window만 옮기고 앱을 앞으로 꺼내지 않는다

창의 `kAXMainAttribute`는 설정 가능하고(`kAXFocusedAttribute`는 창에서 설정 불가), 세우면 그 창이 카카오톡의 key window가 된다. **이때 최전면 앱은 바뀌지 않는다** — 실측 내내 Claude가 앞이었다. 그 뒤 `postToPid`로 보낸 키 이벤트는 그 창으로 간다.

3.3.1의 메커니즘을 반대로 쓰는 방법이라 필요할 때 쓸 수 있다. 대가: 카카오톡이 최전면이고 사용자가 다른 방에 타이핑 중이면 그 타건이 옮겨간 창으로 들어간다. 쓰려면 `AccessibilityMessageSender.mayTakeTheKeyboard`와 같은 관문이 필요하고, 끝나면 원래 main 창을 되돌려야 한다.

현재 전송 경로는 이것을 쓰지 않는다. 전송 버튼 누르기로 충분하기 때문이다.

### 3.4 뚜껑을 닫으면 AX 창 목록이 0이 된다

세션이 잠기지 않아도 그렇다. 3.1이 Space 전환에서 관찰한 것과 같은 증상이고, 원인이 하나 더 있는 것이다. 2.1의 "뚜껑 닫힘 → 전송 성공"은 창 목록을 먼저 읽어야 하는 경로에서는 성립하지 않는다.

측정 (2026-08-09 · 뚜껑 닫힘 · 외장 모니터 없음 · TalkFlow가 `NoDisplaySleep` 유지 중):

```
kCGSSessionOnConsoleKey = true      세션은 잠기지 않았다
AppleClamshellState     = Yes
CGDisplayIsAsleep(main) = false     ← 뚜껑과 무관하게 계속 awake
CGGetActiveDisplayList  = 1 (내장)  ← 뚜껑과 무관하게 계속 1
katok send --list-windows → {"open_windows":[]}
```

창을 못 찾으면 katok은 그 방을 **연다.** 방을 여는 것은 화면이 필요한 작업이라, 타이핑이 멈추기를 기다리는 기본 동작에서는 거부된다.

```
--focus-wait 3    → Error: you kept using the keyboard or mouse for 3s, and this
                    send needs to bring KakaoTalk forward. Nothing was sent.
--take-focus-now  → {"resolved":true,"room":"hangyeol"}
```

`IOPMAssertionDeclareUserActivity`로 디스플레이를 깨우면 창 목록이 즉시 3개로 돌아온다. AX 창 열거는 **켜진 화면**에 딸려 있다.

2.3의 경고가 여기서 그대로 적용된다. 이 상태는 `CGDisplayIsAsleep`으로도 활성 디스플레이 개수로도 알 수 없다. TalkFlow 자신의 `NoDisplaySleep`이 디스플레이를 논리적으로 켜 둔 상태로 만들기 때문이고, 그래서 그 값들을 뚜껑으로 읽는 것은 순환이다. 뚜껑은 `AppleClamshellState`로만 읽는다.

닫힌 뚜껑 뒤에서는 포커스를 뺏는 대가가 눈에 보이지 않으므로, 그때만 즉시 뺏는다. 단 뚜껑이 닫혀도 외장 모니터가 데스크톱을 그리고 있으면 보는 사람이 있다 — 클램셸이 정확히 그 경우다.

### 3.5 대화 목록은 보이는 행만 노출하고, 최근 활동순으로 정렬된다

닫힌 방에 보내려면 그 방을 열어야 하고, 여는 방법은 대화 목록에서 그 행을 찾는 것뿐이다. 그런데 테이블은 화면에 보이는 행만 내놓는다. `AXRows`도 `AXVisibleRows`와 같은 수를 돌려준다.

```
AXRows = 5   AXVisibleRows = 5   AXChildren = 6   AXRowCount = 없음
```

목록 아래쪽 방은 트리에 존재조차 하지 않으므로 이름으로 찾을 수 없다. 같은 한계가 kakaocli에도 있다 — `findChatRow`가 테이블의 자식만 훑고, 못 찾으면 그대로 실패한다. 스크롤하며 탐색하는 구현은 공개된 것이 없다.

이 한계를 견딜 만하게 만드는 것은 정렬 순서다. 목록은 **최근 활동순**이라 답장할 방은 거의 항상 위쪽에 있다. 서로 독립된 두 출처가 같은 순서를 준다(2026-08-09 실측).

```
AX 목록 (위→아래)             아카이브 방별 최신 메시지
달빛 스튜디오      오전 2:51  달빛 스튜디오      17:51
늦반딧불 등산모임  오전 2:44  늦반딧불 등산모임  17:45
hangyeol           오전 2:34  hangyeol           17:34
```

측정한 계정은 대화방이 4개뿐이라 **방이 많을 때 실제로 몇 행까지 노출되는지는 확인하지 못했다.** `AXRows == AXVisibleRows`가 가상화를 가리킬 뿐 증명은 아니다.

확인: 목록 행의 이름과 시각을 읽어 내림차순인지 보고, `SELECT chat_name, MAX(timestamp) ... GROUP BY chat_id ORDER BY MAX(timestamp) DESC`와 대조한다.

### 3.6 닫힌 방을 여는 방법은 화면을 반드시 가져간다

행을 선택하고 Return을 보내면 열린다. 단 Return이 **전역 이벤트**여야 하고, 그래서 카카오톡이 먼저 앞에 나와야 한다. `postToPid`로 보낸 Return은 행이 선택된 상태에서도 아무 일도 하지 않았다. 행에는 `AXPress`도 없고 `AXCustomActions`도 비어 있다.

kakaocli도 같은 순서다: `activate` → 채팅 탭 `AXPress` → 행 선택 → 전역 Return → 실패 시 스크롤 후 전역 더블클릭. 2019년의 한 AppleScript 시도는 특정 대화창 열기를 아예 포기했다.

즉 **포커스를 뺏지 않고 닫힌 방을 여는 길은 알려진 것이 없다.** 3.3의 전송과 달리 여는 것은 공짜가 아니다. 커서 좌표와 이전 최상위 앱은 되돌릴 수 있고, 실측에서 되돌아왔다.

---

## 4. 동기화 비용

`katok sync`는 **신규 메시지가 0건이어도 원본을 전부 다시 읽는다.** 메시지 42만 건 기준 약 2.9초(원본 읽기 1.7초 + 반영 1.2초)로 일정하다.

| 구간 | 소요 |
| --- | --- |
| 파일 변경 감지 | 최대 1초(폴링 주기) |
| `katok sync` 1회 | 약 2.9초 |
| 감지부터 아카이브 반영까지 | 약 4초 |

그래서 동기화 사이에 최소 간격(5초)을 둔다. 대화가 활발할 때 연속 실행되면 코어 하나를 계속 먹는다.

**감지 대상에서 `-shm` 파일은 반드시 제외한다.** SQLite는 읽기만 해도 이 파일을 갱신하므로, 동기화 자신의 읽기가 새 활동으로 보여 무한 동기화가 된다. 쓰기에서만 움직이는 본 DB와 `-wal`만 본다.

---

## 5. Codex CLI

`codex exec`를 다음 조합으로 부른다.

| 플래그 | 이유 |
| --- | --- |
| `--sandbox read-only` | 모델이 명령을 실행할 수 없게 |
| `--ephemeral` | 대화 내용이 Codex 세션 기록에 남지 않게 |
| `--output-schema` | 응답을 해석이 아니라 파싱으로 받기 |
| `--skip-git-repo-check` | 저장소 밖에서 실행하므로 |
| 본문은 stdin | 프로세스 인자는 같은 기기의 다른 프로세스에 그대로 보인다 |
| `--image <FILE>` | 사진 첨부. 이미지는 stdin으로 보낼 수 없다 |

왕복 약 10초.

`--image`는 값을 여러 개 받는 옵션이라 **뒤에 오는 토큰이 플래그처럼 보이지 않으면 그것도 파일 이름으로 먹는다.** stdin을 뜻하는 `-`가 정확히 그런 토큰이다. 그래서 이미지 인자를 맨 앞에 두고 그 뒤에 플래그가 오게 배치한다.

확인 (2026-08-09 · codex-cli 0.147.0): 글자를 그려 넣은 합성 PNG 한 장을 `--image`로 붙이고 본문은 stdin으로 넣었더니, 스키마에 맞는 JSON 안에 그 글자가 그대로 돌아왔다.

프롬프트 주의: 모델에게 침묵을 요구하는 범위를 넓게 잡으면 **일상 대화까지 침묵한다.** "되돌리기 어려운 내용은 답하지 마라"로 썼더니 *"토요일 아침 8시 어때?"* 에 답하지 않았다. 약속을 잡는 대화는 이 제품의 주 용도다. 금전·인증정보로 좁힌 뒤 정상 동작을 확인했다.

### 5.1 모델 목록을 알려 주는 명령은 없다

`codex --help`와 `codex exec --help` 어디에도 모델을 열거하는 곳이 없고, `models`나 `model list` 같은 하위 명령도 없다. 목록이 있는 곳은 `~/.codex/models_cache.json` 하나다. CLI가 자기 필요에 따라 갱신하는 비공개 파일이라 TalkFlow는 읽지 않고 이름만 베껴 둔다. 형식이 바뀌면 답장이 전부 죽고, 이름이 낡으면 선택 항목 하나가 낡을 뿐이다.

확인 (2026-08-11 · codex-cli 0.147.0): 캐시에 8개가 있고 그중 `visibility: "list"`이면서 `supported_in_api: true`인 것이 6개다.

| slug | 캐시의 설명 | 비고 |
| --- | --- | --- |
| `gpt-5.6-sol` | Latest frontier agentic coding model | 이 기기의 `config.toml` 기본값 |
| `gpt-5.6-terra` | Balanced agentic coding model for everyday work | |
| `gpt-5.6-luna` | Fast and affordable agentic coding model | |
| `gpt-5.5` | Frontier model for complex coding, research, and real-world work | |
| `gpt-5.4` | Strong model for everyday coding | 캐시가 곧 폐기 예정이라며 `gpt-5.6-terra`로 유도 |
| `gpt-5.4-mini` | Small, fast, and cost-efficient model for simpler coding tasks | 같은 방식으로 `gpt-5.6-luna`로 유도 |

숨은 둘은 `gpt-5.6-sol-wm`(Work Mode 라우팅 별칭, 캐시가 API 미지원으로 표시)과 `codex-auto-review`(Codex가 자기 명령을 검토하는 모델)다. **캐시에 이름이 있다는 것은 동작한다는 증거가 아니다.** 위 8개와 숨은 둘을 모두 TalkFlow와 같은 잠근 호출로 한 번씩 실제로 돌려서 스키마에 맞는 응답이 돌아오는 것을 확인했다.

추론 강도는 축이 다르다. 캐시의 `supported_reasoning_levels`는 `low·medium·high·xhigh·max·ultra`이고 모델마다 다르다(`gpt-5.6-luna`는 `ultra`가 없고, `gpt-5.5`·`gpt-5.4`는 `xhigh`까지다). **`codex exec`에는 이것을 넘기는 플래그가 없다.** `-c model_reasoning_effort=high`처럼 설정 덮어쓰기로만 넘길 수 있다.

### 5.2 모르는 모델 이름은 CLI가 아니라 API가 거절한다

`--model`에 없는 이름을 줘도 CLI는 그대로 받아들이고 실행한다. 실패는 요청이 나간 뒤에 온다.

```text
$ codex exec … --model not-a-real-model-xyz -
warning: Model metadata for `not-a-real-model-xyz` not found. Defaulting to fallback metadata
ERROR: {"type":"error","status":400,"error":{"type":"invalid_request_error",
  "message":"The 'not-a-real-model-xyz' model is not supported when using Codex with a ChatGPT account."}}
```

그래서 "모델 선택 안 함"은 빈 문자열이 아니라 **플래그 자체를 빼는 것**이어야 한다. `--model ''`은 매 호출을 실패시킨다.

요청이 실패하면 종료 코드는 **1**이고 `--output-last-message` 파일은 만들어지지 않는다. TalkFlow는 종료 코드로 먼저 걸러 내므로 이 경우 "응답을 이해하지 못했습니다"가 아니라 호출 실패로 잡히고, 마지막 두 줄이 이유로 남는다.

### 5.3 "at capacity"는 일시적이고 모델을 가리지 않는다

`ERROR: Selected model is at capacity. Please try a different model.` 는 그 모델이 이 계정에 없다는 뜻이 아니다.

확인 (2026-08-11 · codex-cli 0.147.0): `gpt-5.6-luna`가 이 오류로 3번 연속 실패한 뒤 4·5번째에 성공했고, 그 사이 첫 시도에 성공했던 `gpt-5.6-terra`가 같은 오류를 냈다. 이 문구를 권한 문제로 읽고 선택 목록에서 모델을 빼면 안 된다. 재시도로 구별한다.

---

## 6. 카카오톡 계정 제약

한 계정에 **폰 1대 + PC 1대**가 한계다. 다른 PC에서 로그인하면 기존 PC 접속이 끊긴다.

이 제약은 배포 형태를 결정한다. 맥미니를 상시 봇으로 쓰면 맥북에서 카카오톡을 쓸 수 없다. 안드로이드 봇이 흔한 이유도 여기 있다 — 본인 폰에서 돌리면 새 슬롯을 쓰지 않는다.

---

## 7. 사진 추출

### 7.1 사진 메시지는 `type_2`다

아카이브의 `message_type`은 측정한 계정 기준으로 `text` 1321건, `type_2` 34건, `type_0` 21건, 그 밖에 `type_26`·`type_71`·`type_16385`·`type_12`가 있다. `type_2`가 사진이고 그 `text` 컬럼에는 `사진`(또는 `photo`)만 들어 있다. **`type_0`은 시스템 피드 행이고 `text`가 `{"feedType":25,...}` 같은 JSON이다.**

텍스트가 아닌 것을 한 덩어리로 묶으면 사진과 피드 행을 구분할 수 없다. 피드 행에 대해 미디어 추출을 부르는 것은 아무것도 돌려주지 않는 프로세스 실행이다.

확인: `sqlite3 archive.sqlite3 "SELECT message_type, COUNT(*) FROM messages GROUP BY 1"`

### 7.2 `katok media get`은 종료 코드로 성공을 말하지 않는다

```
katok media get --chat <chatId> --log <logId> --out <dir> --kind photo --no-cdn --json
```

메시지 id는 `<chatId>-<logId>`이고 katok이 원하는 것은 뒤쪽 `logId`다. 사진이 없는 로그를 물어도 **종료 코드는 0이고 `records`가 빈 배열로 온다.** 성공 판정은 `records`로 한다. `--kind`는 소문자 `photo`, `video`, `file`만 받는다.

### 7.3 `--no-cdn`은 대체로 썸네일을 준다

`--no-cdn`은 로컬 캐시·썸네일 계층만 쓴다. 실측한 세 건 모두 `"tier":"thumb"`, `"tier_reason":"full-not-cached"`였고, 파일 이름에 접미사가 붙어 `<logId>_thumb.jpg`가 되었다. **원본 이름을 가정하지 말고 `records[].path`를 읽는다.** 썸네일도 864×1438 정도라 화면 캡처의 글자를 읽을 수 있었다.

### 7.4 비용은 사진 수가 아니라 호출 수다

| 호출 | 소요 |
| --- | --- |
| `--log` 한 건 | 약 0.75초 |
| `--limit 3` (방 전체에서 최근 3장) | 약 0.75초 |
| `--log` 세 번 | 약 2.5초 |

대부분이 프로세스 시작과 DB 열기 비용이다. 그런데도 TalkFlow는 메시지별 `--log` 호출을 쓴다. 방 단위 질의는 "이 방의 최근 사진"을 답하는 것이라, 아카이브가 카카오톡보다 뒤처져 있으면 **모델이 본 적 없는 메시지의 사진**을 돌려준다. 프롬프트는 첨부한 사진마다 어느 메시지의 것인지 말하므로, 추출도 그 단위로 물어야 한다.

측정: 2026-08-09 · katok 0.3.0 · 사진 3장

---

## 8. 방 크기와 대화 속도

채팅방 요약([DESIGN.md 5.3.1](../DESIGN.md#531-채팅방-요약))의 조각 크기와 갱신 문턱을 정하려고 아카이브를 세어 본 값이다.

| 방 | 메시지 | 서로 다른 발신자 | 기간 | 하루 환산 |
| --- | --- | --- | --- | --- |
| 1 | 1,609 | 86 | 1.46일 | 약 1,100 |
| 2 | 504 | 26 | 0.56일 | 약 900 |
| 3 | 121 | 10 | 0.10일 | 약 1,200 |
| 4 | 95 | 2 | 1.25일 | 약 76 |
| 5·6 | 각 1 | 1 | — | — |

**이 값은 곧 커진다.** 카카오톡은 대화방을 열어야 그 방을 동기화하므로, 계정을 바꾼 직후의 이력은 어리다. 위 표는 며칠치일 뿐이고 같은 방이 며칠 사이에도 자랐다.

두 가지를 결정한다.

**요약 조각은 120개로 묶는다.** 답장 창(30개)의 네 배다. 가장 작은 실사용 방은 통째로 읽히고, 큰 방은 상한에 걸린다. 상한이 없으면 "처음 요약"의 크기를 사용자가 앱을 얼마나 오래 썼는지가 정한다.

**갱신 문턱은 새 메시지 40개로 둔다.** 답장 창이 30개라, 그보다 자주 갱신하면 프롬프트가 아직 원문으로 들고 있는 대화를 다시 요약하는 셈이 된다. 40개면 가장 바쁜 방에서 하루 27회쯤이고, 같은 방의 답장 판단이 하루 최대 1,100회이므로 몇 퍼센트가 붙는다.

측정: 2026-08-09 · `archive.sqlite3`를 읽기 전용으로 열어 측정한 계정의 `messages`를 `chat_id`로 집계 · 방 이름과 본문은 읽지 않았다

---

## 8. TCC 신원과 앱 번들

### 8.1 맨 실행 파일은 자기 TCC 신원이 없다

`swift build`가 만드는 실행 파일에는 번들도 서명 신원도 없다. macOS는 이런 프로세스의 권한 요청을 **책임 프로세스**(그것을 실행시킨 터미널이나 에디터)에게 묻는다.

관측: 개발 중 카카오톡 컨테이너를 읽을 때마다 **`'claude'이(가) 다른 앱의 데이터에 접근하려고 합니다`** 가 떴다. 요청 주체가 TalkFlow가 아니라 그것을 띄운 도구였다.

거기에 SwiftPM의 adhoc 서명은 빌드마다 cdhash가 달라진다. 한 번 허용해도 다음 빌드에서 다른 프로그램으로 취급돼 처음부터 다시 묻는다.

Developer ID로 서명한 번들은 designated requirement가 **번들 ID + 팀 ID** 기준이라 재빌드해도 같은 신원이다.

```
designated => identifier "<YOUR-BUNDLE-ID>" and anchor apple generic
              and certificate leaf[subject.OU] = "<YOUR-TEAM-ID>"
```

**따라서 이 앱은 `scripts/build-app.sh --install`로 설치한 번들로만 제대로 돌아간다.** 빌드 산출물을 직접 실행하면 권한이 매번 초기화되고, 요청 창은 엉뚱한 앱 이름으로 뜬다.

부수: katok을 `Contents/Resources/katok`에 넣어 같은 신원 아래에서 돌게 했다. `KatokConnection.findExecutable`이 그 경로를 가장 먼저 본다.

### 8.2 권한 없는 컨테이너 열거는 에러가 아니라 무한 블록이다

`contentsOfDirectory`가 권한 없는 컨테이너를 향하면 `EPERM`도, 예외도, 취소도 없다. 스레드가 syscall 안에 머물고, 동의가 올 때까지 돌아오지 않는다. 동의는 영원히 안 올 수 있다 — 권한 대화상자는 최전면 앱이 있는 화면에 뜨고, 그 화면은 대체로 아무도 안 보는 쪽이다.

2026-08-09 하루에 두 번 당했다. 한 번은 앱 전체가 「감지 중」 초록불을 켠 채 멈췄고, 한 번은 `swift test`가 CPU 0%로 정지했다.

**`try?`로는 못 잡는다.** 던져진 에러를 삼키는 것과 돌아오지 않는 호출은 다른 문제다. 시간 제한을 두고, 넘기면 상태를 「멈춤」으로 바꿔 화면에 그렇게 보이게 해야 한다.

측정: 2026-08-09 · `sample $(pgrep -x TalkFlow)`의 스택이 두 감지 루프 모두 `-[NSFileManager contentsOfDirectoryAtURL:]`에 정지 · `codesign -d --requirements -` 로 designated requirement 확인

### 3.7 멘션 피커는 읽히지만 AX로 고를 수 없다

입력란에 `@`를 대입하면 **멤버 피커가 실제로 뜬다.** 창의 새 `AXScrollArea > AXTable`이고, 행마다 이름이 `AXStaticText`로 들어 있다. 내 계정 행에는 `desc="badge me"`가 붙는다.

고르는 쪽은 다르다.

| 방법 | 결과 |
| --- | --- |
| 행 `AXSelected = true` | **성공을 반환하고 아무 일도 안 한다** (3.3.3의 정반대) |
| 테이블 `AXSelectedRows` | 같음 |
| 행·셀 `AXPress` | 액션 자체가 없다 |
| 프로세스로 마우스 클릭 | 무반응 |
| `AXMain` + pid로 방향키 | **선택이 움직인다** (3.3.4) |

마지막 방법만 통하고, 그 선택 상태는 `AXSelected`로 읽을 수 있어 커밋 전 검증이 가능하다. Return으로 커밋했을 때 진짜 멘션이 되는지는 **확인하지 않았다.**

거기서 멈춘 이유는 메커니즘이 아니라 **동일 닉네임**이다. 피커는 이름만 주고 `sender_id`를 주지 않는다.

처음 이 문단에는 중복이 213건이라고 적었는데 **틀렸다.** 아카이브는 동기화한 모든 계정을 한 파일에 담고(1.4), 그 쿼리에 `account_hash` 필터가 없었다. 213건은 대부분 로그아웃한 계정 것이다.

측정한 계정 기준으로 다시 세면 같은 방 안 닉네임 중복은 **3건**이다 — 한 방 안에서 표시 이름 하나에 서로 다른 두 사람이 걸리는 경우가 세 번 나온다. 여기에 TalkFlow 자체 기록에서도 같은 모양이 한 건 더 있었다. 누가 누구인지는 적지 않는다. 건수는 줄었지만 결론은 그대로다: 잘못 고르면 엉뚱한 사람을 부르고, 그건 조용히 실패하지 않는다.

확인: `messages`를 셀 때는 **반드시** `account_hash`로 거른다. 이 문서의 1.2와 1.4가 경고하는 것이 정확히 이 실수다.

**평문 `@이름`은 멘션이 아니다.** 봇 계정에서 `@hangyeol`를 보내고 hangyeol 계정에서 확인했다 — 강조도 알림도 없는 그냥 글자였다. 그래서 이름 태그 옵션은 제거했다.
