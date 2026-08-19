import Foundation
import Testing
import TalkFlowDomain

/// The base every case edits: 멘션 room so an enum change has a visible before, and
/// every other field on its default so a set is told apart from what was already there.
private let base = RoomPolicy(
    accountFingerprint: "fp",
    chatRoomID: "r",
    responseMode: .mentionOnly
)

private func applied(_ field: String, _ value: String, to policy: RoomPolicy = base) -> PolicyEditor.Applied? {
    guard case let .success(a) = PolicyEditor.apply(field: field, value: value, to: policy) else { return nil }
    return a
}

private func failure(_ field: String, _ value: String, to policy: RoomPolicy = base) -> PolicyEditor.Failure? {
    guard case let .failure(f) = PolicyEditor.apply(field: field, value: value, to: policy) else { return nil }
    return f
}

@Test
func responseModeIsSetAndEchoesBeforeAndAfter() {
    let a = applied("응답", "자동")
    #expect(a?.policy.responseMode == .automatic)
    #expect(a?.label == "응답")
    #expect(a?.before == "멘션에만 응답")
    #expect(a?.after == "자동응답")
}

@Test
func deliveryAndOpenerReadTheirTokens() {
    #expect(applied("전송", "상시")?.policy.deliveryMode == .always)
    #expect(applied("전송", "초안")?.policy.deliveryMode == .draftOnly)
    #expect(applied("먼저말", "전송")?.policy.conversationOpener == .delivers)
    #expect(applied("먼저말", "끔")?.policy.conversationOpener == .off)
}

@Test
func interjectionTakesAPercentAndRefusesOutOfRange() {
    #expect(applied("끼어들기", "30")?.policy.interjectionChance.percent == 30)
    #expect(applied("끼어들기", "30%")?.policy.interjectionChance.percent == 30)
    #expect(failure("끼어들기", "150") == .badValue(label: "끼어들기", allowed: "0~100"))
    #expect(failure("끼어들기", "높음") == .badValue(label: "끼어들기", allowed: "0~100"))
}

@Test
func togglesReadKemAndKkeumAndLeaveTheRestAlone() {
    #expect(applied("사진", "켬")?.policy.readsPhotos == true)
    #expect(applied("웹검색", "끔")?.policy.webSearch == false)
    #expect(applied("사람기억", "켬")?.policy.remembersPeople == true)
    let burning = applied("집중시간", "켬")
    #expect(burning?.policy.burning.isEnabled == true)
    // 켬은 isEnabled만 뒤집고 나머지 버닝 세부값은 그대로 둔다.
    #expect(burning?.policy.burning.chance == base.burning.chance)
    #expect(burning?.policy.burning.duration == base.burning.duration)
    #expect(failure("사진", "아마도") == .badValue(label: "사진", allowed: "켬·끔"))
}

@Test
func minimumIntervalParsesDurations() {
    #expect(applied("최소간격", "5분")?.policy.minimumInterval == 300)
    #expect(applied("최소간격", "30초")?.policy.minimumInterval == 30)
    #expect(applied("최소간격", "1시간")?.policy.minimumInterval == 3600)
    #expect(applied("최소간격", "없음")?.policy.minimumInterval == 0)
    #expect(applied("최소간격", "5분")?.after == "5분")
    #expect(failure("최소간격", "이따가") == .badValue(label: "최소간격", allowed: "없음·30초·5분·1시간"))
}

@Test
func activeHoursTakeAlwaysOrAClockRange() {
    #expect(applied("활성시간", "항상")?.policy.activeHours.isLimited == false)
    let window = applied("활성시간", "09:00-23:00")?.policy.activeHours
    #expect(window?.isLimited == true)
    #expect(window?.startMinute == 9 * 60)
    #expect(window?.endMinute == 23 * 60)
    // 파서가 이어붙인 값에 공백이 섞여도 파싱된다.
    #expect(applied("활성시간", "09:00 - 23:00")?.policy.activeHours.startMinute == 9 * 60)
    #expect(failure("활성시간", "25:00-26:00") == .badValue(label: "활성시간", allowed: "항상·09:00-23:00"))
    #expect(failure("활성시간", "저녁") == .badValue(label: "활성시간", allowed: "항상·09:00-23:00"))
}

@Test
func anUnknownFieldFailsAsSuch() {
    #expect(failure("말투", "친근하게") == .unknownField)
    #expect(failure("없는항목", "값") == .unknownField)
}

@Test
func aValueThatChangesNothingStillEchoesTheSameWordTwice() {
    // base는 이미 멘션. 다시 멘션으로 세팅하면 before == after 로 무변경이 드러난다.
    let a = applied("응답", "멘션")
    #expect(a?.before == "멘션에만 응답")
    #expect(a?.after == "멘션에만 응답")
    #expect(a?.policy.responseMode == .mentionOnly)
}

@Test
func describeReportsAFieldsCurrentValueAndOptions() {
    // base는 멘션, 최소간격 기본 300초 = 5분.
    let response = PolicyEditor.describe(field: "응답", in: base)
    #expect(response?.label == "응답")
    #expect(response?.current == "멘션에만 응답")
    #expect(response?.allowed == "끔·감지·멘션·자동")
    #expect(PolicyEditor.describe(field: "사진", in: base)?.allowed == "켬·끔")
    #expect(PolicyEditor.describe(field: "최소간격", in: base)?.current == "5분")
    #expect(PolicyEditor.describe(field: "없는항목", in: base) == nil)
}

@Test
func everyAdvertisedFieldCanBeDescribed() {
    // 목록에 광고한 항목은 전부 describe 되어야 한다 — 세 switch가 어긋나지 않게.
    #expect(PolicyEditor.settableFields.count == 19)
    for field in PolicyEditor.settableFields {
        #expect(PolicyEditor.describe(field: field, in: base) != nil)
    }
}

/// 목록·설명·선택지가 한 표에서 나온다는 것을, 표를 보지 않고 밖에서 확인한다. 예전
/// 네 갈래 switch에서는 이 중 어느 하나가 빠져도 나머지가 태연히 답했다.
@Test
func everyAdvertisedFieldNamesItselfAndOffersOptions() {
    // 순서까지 박아 둔다 — `!방 <N>`이 읽는 순서이고 `!세팅 <N>` 목록이 그 순서로 찍힌다.
    #expect(PolicyEditor.settableFields == [
        "응답", "전송", "끼어들기", "최소간격", "판단주기", "활성시간", "답장",
        "사진", "웹검색", "링크", "대화기억", "사람기억", "집중시간",
        "먼저말", "먼저말주기", "먼저말시간", "먼저말반복", "먼저말주제", "먼저말정지",
    ])
    for field in PolicyEditor.settableFields {
        let info = PolicyEditor.describe(field: field, in: base)
        #expect(info?.label == field, "\(field): describe가 다른 이름으로 답한다")
        #expect(info?.allowed.isEmpty == false, "\(field): 선택지가 빈 문자열이다")
        #expect(info?.current.isEmpty == false, "\(field): 지금 값이 빈 문자열이다")
        // 항목이 있으면 값 파싱까지 반드시 있다 — 광고만 하고 못 받는 항목은 없다.
        #expect(failure(field, "그럴리가없는값") == .badValue(label: field, allowed: info?.allowed ?? ""))
    }
}

/// 항목 이름이 두 번 적히지 않았다.
///
/// switch였을 때는 컴파일러가 「case is already handled」로 잡아 줬는데, 표로 바꾸면서
/// 그 검사가 없어졌다. 이름이 겹치면 뒤에 적힌 항목이 조용히 죽고 — 목록에는 두 번
/// 찍히는데 !세팅은 첫 번째 것만 쓴다 — 이 테스트가 그 자리를 대신한다.
@Test
func everyFieldLabelIsWrittenOnce() {
    let labels = PolicyEditor.settableFields
    #expect(Set(labels).count == labels.count, "항목 이름이 겹친다: \(labels)")
}

/// 기본 정책에서 「지금 값」을 그대로 다시 넣으면 같은 정책이 나온다 — current가 찍는
/// 단어를 write가 못 읽으면 여기서 드러난다. 운영자가 화면에 보이는 값을 그대로
/// 따라 치는 것이 가장 흔한 입력이라, 이게 어긋나면 바로 「그런 값이 아니에요」가 된다.
///
/// **아래 세 항목은 오늘 실제로 되먹여지지 않는다.** 이번 패스는 표를 하나로 모으는
/// 것이고 답을 바꾸지 않으므로, 고치지 않고 실측 문자열로 못 박아 둔다.
/// - 응답: `.mentionOnly.title`은 「멘션에만 응답」인데 `responseMode`는 멘션·멘션만·
///   멘션에만까지만 읽는다.
/// - 먼저말주기: `summary`가 「30분~3시간마다」 — 「마다」가 붙어 있어 파서가 단위를 못 찾는다.
/// - 먼저말반복: current는 「0회」, write는 `Int("0회")` = nil.
private let currentValuesTheWriterCannotReadBack = [
    "응답": "멘션에만 응답",
    "먼저말주기": "30분~3시간마다",
    "먼저말반복": "0회",
]

@Test
func everyFieldsOwnCurrentValueGoesBackInUnchanged() {
    for field in PolicyEditor.settableFields {
        guard let info = PolicyEditor.describe(field: field, in: base) else {
            #expect(Bool(false), "\(field): describe가 nil")
            continue
        }
        if let unreadable = currentValuesTheWriterCannotReadBack[field] {
            #expect(info.current == unreadable, "\(field): 못 읽는 값의 문자열이 바뀌었다")
            #expect(failure(field, info.current) == .badValue(label: field, allowed: info.allowed))
            continue
        }
        let round = applied(field, info.current)
        #expect(round != nil, "\(field): 지금 값 「\(info.current)」을 되먹일 수 없다")
        #expect(round?.policy == base, "\(field): 같은 값을 넣었는데 정책이 달라졌다")
        #expect(round?.before == info.current)
        #expect(round?.after == info.current)
    }
}

/// 같은 되먹임 결함이 기본값 밖에서도 있다 — 어느 값에 걸려 있는지 문자열로 남긴다.
/// 전부 「지금 값 그대로」인데 거부되는 경우이고, 이번 패스에서 고치지 않는다.
@Test
func otherCurrentValuesThatDoNotGoBackInAreRecordedAsTheyAre() {
    func refused(_ field: String, _ policy: RoomPolicy) -> String? {
        guard let info = PolicyEditor.describe(field: field, in: policy) else { return nil }
        guard failure(field, info.current, to: policy) != nil else { return nil }
        return info.current
    }
    var idle = base; idle.deliveryMode = .autoSendWhenIdle
    #expect(refused("전송", idle) == "유휴 상태 자동 전송")
    var always = base; always.deliveryMode = .always
    #expect(refused("전송", always) == "상시 전송")
    var fresh = base; fresh.openerRepeatTopic = .fresh
    #expect(refused("먼저말주제", fresh) == "새 주제")
    var batched = base; batched.judgementInterval = JudgementInterval(fixed: 300)
    #expect(refused("판단주기", batched) == "5분마다")
    // summary는 EN DASH(–)로 잇는데 파서는 하이픈(-)과 물결(~)만 자른다.
    var window = base
    window.activeHours = ReplyActiveHours(isLimited: true, startMinute: 9 * 60, endMinute: 23 * 60)
    #expect(refused("활성시간", window) == "09:00–23:00")
}

/// 없는 항목은 apply와 describe가 같은 답을 해야 한다: 예전에는 `allowed`에서만 빠지면
/// apply는 「그런 항목이 없어요」, describe는 nil, 목록에는 남아 있는 식으로 갈렸다.
///
/// 말투와 답변 조건이 여기 있는 이유는 자유 문장이라 콘솔에서 손대지 못하게 둔 것이고,
/// 표에 항목이 없다는 것이 그 울타리 전부다.
@Test
func anUnknownFieldGetsTheSameAnswerFromApplyAndDescribe() {
    for field in ["말투", "답변 조건", "답변조건", "없는항목", "", "응 답", "사진 "] {
        #expect(PolicyEditor.settableFields.contains(field) == false, "\(field): 목록에 있다")
        #expect(PolicyEditor.describe(field: field, in: base) == nil, "\(field): describe가 답했다")
        #expect(failure(field, "켬") == .unknownField, "\(field): apply가 받았다")
    }
}

@Test
func judgementIntervalParsesImmediateFixedRangesAndRefusesMixedUnits() {
    #expect(applied("판단주기", "즉시")?.policy.judgementInterval == .immediate)
    #expect(applied("판단주기", "5분")?.policy.judgementInterval == JudgementInterval(fixed: 300))
    #expect(applied("판단주기", "10개")?.policy.judgementInterval == JudgementInterval(measure: .messages, shortest: 10, longest: 10))
    #expect(applied("판단주기", "5분~10분")?.policy.judgementInterval == JudgementInterval(shortest: 300, longest: 600))
    #expect(applied("판단주기", "5분")?.after == "5분마다")
    // 단위 혼용은 거부.
    #expect(failure("판단주기", "5분~10개") == .badValue(label: "판단주기", allowed: "즉시·10개·5분·5분~10분"))
}

@Test
func openerSubFieldsSetTimeRepeatTopicAndToggles() {
    // 먼저말 주기는 시간만 — 개(메시지)는 오프너가 못 써서 거부.
    #expect(applied("먼저말주기", "3시간")?.policy.conversationOpenerInterval == JudgementInterval(fixed: 3 * 3600))
    #expect(failure("먼저말주기", "10개") == .badValue(label: "먼저말주기", allowed: "3시간·2시간~6시간"))
    // 먼저말 시간은 활성시간과 같은 파싱.
    #expect(applied("먼저말시간", "22:00-08:00")?.policy.conversationOpenerHours.isLimited == true)
    #expect(applied("먼저말시간", "항상")?.policy.conversationOpenerHours.isLimited == false)
    // 반복 횟수·주제, 정지·답장 토글.
    #expect(applied("먼저말반복", "3")?.policy.openerRepeatLimit == 3)
    #expect(failure("먼저말반복", "100") == .badValue(label: "먼저말반복", allowed: "0~99"))
    #expect(applied("먼저말주제", "새주제")?.policy.openerRepeatTopic == .fresh)
    #expect(applied("먼저말정지", "켬")?.policy.openerCadencePausesOutsideHours == true)
    #expect(applied("답장", "끔")?.policy.answersReplies == false)
}
