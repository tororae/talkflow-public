import Foundation
import Testing
import TalkFlowDomain
@testable import TalkFlowApplication

/// The room the two views are printed for. Every policy field on its default, so
/// what the two commands disagree about is the wording and not the value.
private let wordingRoom = ChatRoom(id: "wording-room", displayName: "프로젝트 팀", kind: .group)
private let wordingPolicy = RoomPolicy(
    accountFingerprint: "fp",
    chatRoomID: wordingRoom.id,
    responseMode: .mentionOnly
)

/// The same room on one stated cadence, for the fields whose default is the one
/// value that prints without a number in it.
private func judging(_ interval: JudgementInterval) -> RoomPolicy {
    var policy = wordingPolicy
    policy.judgementInterval = interval
    return policy
}

/// `!방 <N>`'s settings card and `!세팅 <N> <항목>`'s field view, as the handler
/// builds them — the two seams a value's wording crosses.
private func card(_ policy: RoomPolicy = wordingPolicy) -> String {
    AdminCommandResponder.room(
        AdminCommandResponder.NumberedRoom(number: 3, room: wordingRoom, policy: policy),
        windowOpen: nil
    )
}

private func field(_ name: String, in policy: RoomPolicy = wordingPolicy) -> String? {
    guard let info = PolicyEditor.describe(field: name, in: policy) else { return nil }
    return AdminCommandResponder.settingField(roomNumber: 3, roomName: wordingRoom.displayName, info: info)
}

/// The bug this pins: `!방 3` printed 「집중시간: 꺼짐」 and `!세팅 3 집중시간` printed
/// 「지금: 끔」 for the same stored `false`, because the app layer and the domain each
/// carried a formatter and one of them drifted. One word now, and 끔 rather than
/// 꺼짐 because that is the word `!세팅` advertises as the value it takes.
@Test
func theRoomCardAndTheSettingFieldSayOneWordForABurningRoomThatIsOff() {
    #expect(card().contains("집중시간: 끔"))
    #expect(field("집중시간")?.contains("지금: 끔") == true)
    #expect(card().contains("집중시간: 꺼짐") == false)
}

/// The same crossing for every other toggle, so the next formatter added to one
/// side and not the other fails here rather than in a room.
@Test
func everyToggleReadsTheSameOnTheRoomCardAndInItsField() {
    let toggles: [(name: String, on: Bool)] = [
        ("사진", wordingPolicy.readsPhotos),
        ("웹검색", wordingPolicy.webSearch),
        ("링크", wordingPolicy.readsLinks),
        ("대화기억", wordingPolicy.remembersConversation),
        ("사람기억", wordingPolicy.remembersPeople),
    ]
    // 기본값이 한쪽으로만 쏠려 있으면 켬 쪽 단어는 확인되지 않는다 — 대화기억만 기본 켬이다.
    #expect(Set(toggles.map(\.on)).count == 2)
    for (name, on) in toggles {
        let word = PolicyWording.onOff(on)
        #expect(card().contains("\(name): \(word)"))
        #expect(field(name)?.contains("지금: \(word)") == true)
    }
}

/// And for the span both views print. 최소간격's default is 300초, which reads 5분 on
/// each side rather than 5분 on one and 300초 on the other.
@Test
func aMinimumIntervalReadsTheSameOnTheRoomCardAndInItsField() {
    #expect(wordingPolicy.minimumInterval == 300)
    #expect(card().contains("최소간격: 5분"))
    #expect(field("최소간격")?.contains("지금: 5분") == true)
}

/// 판단주기 is the other span both views print, and the one whose reading carries a
/// 마다 on the end — so it is where a span formatter that answers 「없음」 for a small
/// number surfaces as 「없음마다」. Literals on both sides rather than one expression
/// compared with itself, which would agree however wrong it got.
@Test
func aJudgementCadenceReadsTheSameOnTheRoomCardAndInItsField() {
    #expect(wordingPolicy.judgementInterval == .immediate)
    #expect(card().contains("판단주기: 즉시"))
    #expect(field("판단주기")?.contains("지금: 즉시") == true)

    let ranged = judging(JudgementInterval(shortest: 10, longest: 300))
    #expect(card(ranged).contains("판단주기: 10초~5분마다"))
    #expect(field("판단주기", in: ranged)?.contains("지금: 10초~5분마다") == true)

    let fixed = judging(JudgementInterval(fixed: 300))
    #expect(card(fixed).contains("판단주기: 5분마다"))
    #expect(field("판단주기", in: fixed)?.contains("지금: 5분마다") == true)
}
