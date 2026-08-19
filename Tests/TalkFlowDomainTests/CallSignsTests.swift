import Foundation
import Testing
@testable import TalkFlowDomain

private let room = ChatRoom(id: "room-g", displayName: "달빛 스튜디오", kind: .group)

/// The bug this type exists for: the account's KakaoTalk name was never in the
/// keyword list, so `멘션에만 응답` could not fire once. Nobody types a name
/// somebody registered in settings; they type the name they see in the room.
@Test
func theAccountsOwnNameCountsAsACallWithNothingConfigured() {
    let signs = CallSigns(nickname: "달구지톡")

    #expect(signs.matches("달구지톡 이거 봐줄래?"))
    #expect(signs.matched(in: "달구지톡 이거 봐줄래?") == "달구지톡")
    #expect(signs.matches("이거 누가 확인했죠?") == false)
}

@Test
func theThreeSourcesAddUpInsteadOfReplacingEachOther() {
    let signs = CallSigns(
        nickname: "달구지톡",
        globalKeywords: ["달구봇"],
        roomKeywords: ["달빛"]
    )

    #expect(signs.all == ["달구지톡", "달구봇", "달빛"])
    #expect(signs.matched(in: "달구지톡아 뭐해") == "달구지톡")
    #expect(signs.matched(in: "달구봇 이거 봐줘") == "달구봇")
    #expect(signs.matched(in: "달빛 오늘 일정 뭐야") == "달빛")
}

/// The room's own words are read off the policy so no caller can assemble the
/// set differently from the engine.
@Test
func aRoomsOwnKeywordsComeFromItsPolicy() {
    var policy = RoomPolicy.makeDefault(accountFingerprint: "katok-test", room: room)
    policy.responseKeywords = ["달빛"]

    let signs = CallSigns(nickname: "달구지톡", globalKeywords: ["달구봇"], policy: policy)

    #expect(signs.roomKeywords == ["달빛"])
    #expect(signs.all == ["달구지톡", "달구봇", "달빛"])
}

@Test
func aRoomThatRegisteredNothingStillAnswersToTheNameAndTheGlobalKeywords() {
    let policy = RoomPolicy.makeDefault(accountFingerprint: "katok-test", room: room)

    let signs = CallSigns(nickname: "달구지톡", globalKeywords: ["달구봇"], policy: policy)

    #expect(policy.responseKeywords.isEmpty)
    #expect(signs.roomKeywords.isEmpty)
    #expect(signs.matches("달구지톡 있어?"))
    #expect(signs.matches("달구봇 있어?"))
}

/// One word registered in two places is one word on screen and one comparison
/// at match time.
@Test
func theSameWordRegisteredTwiceIsListedOnce() {
    let signs = CallSigns(
        nickname: "달구지톡",
        globalKeywords: ["달구봇", "달구지톡"],
        roomKeywords: ["DALGUBOT", "dalgubot"]
    )

    #expect(signs.all == ["달구지톡", "달구봇", "DALGUBOT"])
}

/// `@` is how a name is typed in a room, not part of it. Kept, the same word
/// would stop matching a plain call by name.
@Test
func aWordRegisteredWithTheAtSignIsStoredWithoutIt() {
    let signs = CallSigns(nickname: " @달구지톡 ", globalKeywords: ["@달구봇", "   "])

    #expect(signs.nickname == "달구지톡")
    #expect(signs.globalKeywords == ["달구봇"])
}

@Test
func anAccountWithNoNameYetFallsBackToItsKeywords() {
    let signs = CallSigns(nickname: nil, globalKeywords: ["달구봇"])

    #expect(signs.nickname == nil)
    #expect(signs.isEmpty == false)
    #expect(signs.matches("달구봇 있어?"))
    #expect(CallSigns().isEmpty)
    #expect(CallSigns().matches("아무 말") == false)
}

/// Korean particles attach straight onto a noun, so the name has to survive
/// whatever follows it — including the `@` KakaoTalk shows in front.
@Test
func theNameIsStillACallWithAParticleOrATagAttached() {
    let signs = CallSigns(nickname: "달구지톡")

    #expect(signs.matches("달구지톡아 지금 뭐 해?"))
    #expect(signs.matches("@달구지톡 확인 부탁해요"))
    #expect(signs.matches("달구지톡님, 이거 봐주세요"))
    #expect(signs.matches("어제 달구지톡이 말한 거"))
}

/// The user chose their keywords and can delete one that fires too often. The
/// name arrives on its own, so a short one must not answer messages that merely
/// contain those letters.
@Test
func theNameHasToStartWhereAWordStartsButAKeywordDoesNot() {
    let name = CallSigns(nickname: "민")
    let keyword = CallSigns(globalKeywords: ["민"])

    #expect(name.matches("국민연금 신청했어?") == false)
    #expect(name.matches("민 어디야?"))
    #expect(keyword.matches("국민연금 신청했어?"))
}

@Test
func aLatinNameDoesNotFireInsideALongerLatinWord() {
    let signs = CallSigns(nickname: "Ann")

    #expect(signs.matches("Announcement 확인했어?") == false)
    #expect(signs.matches("ann 안녕"))
    #expect(signs.matches("ANN 이거 봐줘"))
    #expect(signs.matches("Ann아 이거 봐줘"))
}
