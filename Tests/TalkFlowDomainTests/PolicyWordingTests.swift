import Foundation
import Testing
import TalkFlowDomain

/// A span reads in the largest unit that keeps it whole, because a bound or an
/// interval printed as "7200초" is a number the reader has to do arithmetic on.
@Test
func aSpanReadsInTheLargestUnitThatKeepsItWhole() {
    #expect(PolicyWording.duration(30) == "30초")
    #expect(PolicyWording.duration(60) == "1분")
    #expect(PolicyWording.duration(3600) == "1시간")
    // 90은 분으로 나뉘지 않으니 초로, 5400은 시간으로 나뉘지 않으니 분으로 내려앉는다.
    #expect(PolicyWording.duration(90) == "90초")
    #expect(PolicyWording.duration(5400) == "90분")
    // 그 자리에서는 두 함수가 같은 답을 낸다. 갈라지는 곳은 0뿐이다.
    for seconds in [30.0, 60, 90, 3600, 5400] {
        #expect(PolicyWording.span(seconds) == PolicyWording.duration(seconds))
    }
}

/// Zero is a state, not a duration: 최소간격 0 means there is no minimum, and "0초"
/// reads as a wait of some length.
@Test
func aFieldsOwnSpanOfNothingReadsAsNoneRatherThanZero() {
    #expect(PolicyWording.duration(0) == "없음")
    // 음수는 저장될 리 없지만, 도달하면 「없음」이 「-1초」보다 안전한 읽기다.
    #expect(PolicyWording.duration(-1) == "없음")
    // 반초는 반올림되어 사라지지 않고 1초로 읽힌다.
    #expect(PolicyWording.duration(0.6) == "1초")
}

/// The half-second band is where the two readings have to differ. `span` keeps a
/// number and a unit because its callers glue a suffix on: 「0시간마다」 is a cadence
/// nobody set, but 「없음마다」 is not Korean at all, and 「없음보다 짧게는 둘 수 없습니다」
/// quotes a bound as if there were none.
@Test
func aSpanSomethingIsAppendedToNeverReadsAsNone() {
    #expect(PolicyWording.span(0) == "0시간")
    #expect(PolicyWording.span(0.4) == "0시간")
    #expect(PolicyWording.duration(0.4) == "없음")
    // 이 값이 실제로 접미사와 붙는 두 자리.
    #expect(JudgementInterval(shortest: 0.4, longest: 0.4).summary == "0시간마다")
    #expect(JudgementIntervalInput.judgement.explanation(.tooShort, in: .seconds).hasPrefix("5초보다"))
}

/// A toggle says 켬/끔 — the two words `PolicyEditor.allowed` advertises as what
/// these fields accept, so the console echoes back what it asked for. It used to
/// say 꺼짐 on `!방 <N>` and 끔 on `!세팅`, which is one stored `false` answered two
/// ways by the same console.
@Test
func aToggleReadsAsTheTwoWordsTheConsoleAsksFor() {
    #expect(PolicyWording.onOff(true) == "켬")
    #expect(PolicyWording.onOff(false) == "끔")
}

/// The wording is what `!세팅 <N> 집중시간` prints as 지금, so the field view and the
/// room card have one word between them rather than a formatter each.
@Test
func theBurningFieldPrintsTheSharedToggleWording() {
    let policy = RoomPolicy(accountFingerprint: "fp", chatRoomID: "r", responseMode: .mentionOnly)

    #expect(PolicyEditor.describe(field: "집중시간", in: policy)?.current == "끔")
    // 광고한 값 목록에 그 단어가 실제로 들어 있어야 에코가 성립한다.
    #expect(PolicyEditor.describe(field: "집중시간", in: policy)?.allowed.contains("끔") == true)
}
