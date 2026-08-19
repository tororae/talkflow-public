import Foundation
import Testing
@testable import TalkFlowDomain

private let account = "katok-interjection"
private let room = ChatRoom(id: "room-g", displayName: "프로젝트 팀", kind: .group)
private let engine = ResponsePolicyEngine()

/// The bug this setting keeps coming back to: words in a picker with one
/// behaviour behind them. 낮음 and 보통 were literally the same value once; then
/// they were told apart by a local rule that threw away plain questions. A
/// percentage has nowhere to hide, and these are the tests that hold it to that.

/// 0% is what 꺼짐 was: the message never costs a call.
@Test
func aRoomAtZeroNeverAsksAboutAMessageNobodyAddressed() {
    let outcome = engine.evaluate(
        evaluation(chance: .never, messages: [spokenMessage(id: "m1", body: "다들 점심 뭐 먹어요?")])
    )

    #expect(outcome == .hold(reason: .interjectionSkipped))
}

/// And 0% is still not 끔. Being called by name ignores the dial, exactly as
/// 꺼짐 did.
@Test
func aCallByNameOutranksAZeroChance() {
    let outcome = engine.evaluate(
        evaluation(chance: .never, messages: [spokenMessage(id: "m1", body: "한결")])
    )

    #expect(outcome == .ask(trigger: .mention, triggerMessageID: "m1"))
}

/// 100% asks about everything, whatever the draw was. The model is what decides
/// whether an answer is wanted — that is the whole reason the dial is about
/// asking rather than about answering.
@Test
func aRoomAtFullChanceAsksWhateverTheDrawWas() {
    for draw in [0.0, 0.5, 0.999, 1.0] {
        let outcome = engine.evaluate(
            evaluation(
                chance: .always,
                messages: [spokenMessage(id: "m1", body: "다들 점심 뭐 먹어요?")],
                roll: InterjectionRoll { _ in draw }
            )
        )

        #expect(outcome == .ask(trigger: .spontaneous, triggerMessageID: "m1"), "draw \(draw)")
    }
}

/// A middle value has to actually skip, or it is the fourth setting in this app
/// that promises a difference it does not make. Both sides of 40% are checked,
/// because a percentage that never skips and one that never asks are the same
/// failure twice.
@Test
func aMiddleChanceSkipsTheDrawsAboveItAndAsksTheOnesBelow() {
    let message = [spokenMessage(id: "m1", body: "다들 점심 뭐 먹어요?")]
    let chance = InterjectionChance(percent: 40)

    let inside = engine.evaluate(
        evaluation(chance: chance, messages: message, roll: InterjectionRoll { _ in 0.39 })
    )
    let outside = engine.evaluate(
        evaluation(chance: chance, messages: message, roll: InterjectionRoll { _ in 0.41 })
    )

    #expect(inside == .ask(trigger: .spontaneous, triggerMessageID: "m1"))
    #expect(outside == .hold(reason: .interjectionSkipped))
}

/// The draw is made from the run being judged, not from a fresh coin. The
/// pipeline re-reads a room after 뒷말 대기 and again on any later sync that
/// reports it changed, and an answer that moved between two of those looks would
/// let a 40% room drop a reply it had already accepted.
@Test
func theSameRoomAndRunDrawTheSameNumberEveryTime() {
    let roll = InterjectionRoll.fromJudgedRun
    let key = "room-g/m1"

    #expect(roll(key) == roll(key))
    #expect(roll(key) != roll("room-g/m2"))
    #expect(roll(key) != roll("room-other/m1"))
}

/// The same thing said in the engine's terms: two judgements of one room and one
/// message agree, whatever the percentage is. Every value is tried because a
/// disagreement would only show up at the percentage the draw happens to
/// straddle.
@Test
func rejudgingTheSameMessageGivesTheSameAnswerAtEveryPercentage() {
    let messages = [spokenMessage(id: "m1", body: "다들 점심 뭐 먹어요?")]

    for percent in 0...100 {
        let chance = InterjectionChance(percent: percent)
        let first = engine.evaluate(evaluation(chance: chance, messages: messages))
        let second = engine.evaluate(evaluation(chance: chance, messages: messages))

        #expect(first == second, "\(percent)% disagreed with itself")
    }
}

/// 뒷말 대기 in the shape the pipeline runs it: the room is read again once the
/// follow-up has landed, and the second reading is told which run the first one
/// accepted. Without the pin the newest message is a different subject and the
/// draw moves with it.
@Test
func theSecondLookAfterTheFollowUpWaitDrawsForTheRunTheFirstOneAccepted() {
    let chance = InterjectionChance(percent: 40)
    let first = [spokenMessage(id: "m1", body: "이거 어떻게 하기로 했었죠")]
    let settled = first + [spokenMessage(id: "m2", body: "아 아니다 내일 얘기해요")]

    // A draw that lands inside 40% for the first message and outside it for the
    // follow-up, which is exactly the disagreement the pin exists to prevent.
    let roll = InterjectionRoll { $0.hasSuffix("m1") ? 0.1 : 0.9 }

    let before = engine.evaluate(evaluation(chance: chance, messages: first, roll: roll))
    let after = engine.evaluate(
        evaluation(chance: chance, messages: settled, roll: roll, answeringFrom: "m1")
    )
    let unpinned = engine.evaluate(evaluation(chance: chance, messages: settled, roll: roll))

    #expect(before == .ask(trigger: .spontaneous, triggerMessageID: "m1"))
    #expect(after == .ask(trigger: .spontaneous, triggerMessageID: "m2"))
    #expect(unpinned == .hold(reason: .interjectionSkipped))
}

/// The dial is not consulted in a 1:1 room. Everything the other person says
/// there is addressed to the user, so there is nothing to interject into.
@Test
func aDirectRoomIgnoresTheChanceEntirely() {
    let direct = ChatRoom(id: "room-d", displayName: "지수", kind: .direct)
    let outcome = engine.evaluate(
        evaluation(
            chance: .never,
            messages: [spokenMessage(id: "m1", body: "내일 시간 돼?")],
            room: direct
        )
    )

    #expect(outcome == .ask(trigger: .directQuestion, triggerMessageID: "m1"))
}

/// The message that ended the local question-detector. It arrived in a 낮음 room
/// and was dropped without a call: it ends `건가..`, the suffix list carried
/// `건가요`, and there is no `?`. Nothing local stands between a message and the
/// model any more — at 100% this reaches it, and whether it wants an answer is
/// the model's to say.
///
/// Written to the shape of the real one rather than copied from it. KakaoTalk
/// text does not go in fixtures.
@Test
func theQuestionThatTheSuffixListDroppedNowReachesTheModel() {
    let asked = "한도 다 차고 쓰지도 않았는데 초기화됐네요. 다음 리셋 날짜만 하루 밀리는건가.."

    let outcome = engine.evaluate(
        evaluation(chance: .always, messages: [spokenMessage(id: "m1", body: asked)])
    )

    #expect(outcome == .ask(trigger: .spontaneous, triggerMessageID: "m1"))
}

/// The value itself refuses to be out of range rather than trusting its caller,
/// and both ends are answered before any arithmetic so neither can come down to
/// a rounding.
@Test
func theChanceStaysInsideItsOwnRange() {
    #expect(InterjectionChance(percent: -20).percent == 0)
    #expect(InterjectionChance(percent: 240).percent == 100)
    #expect(InterjectionChance(percent: 0).admits(0) == false)
    #expect(InterjectionChance(percent: 100).admits(1) == true)
    #expect(InterjectionChance(percent: 50).summary == "50%")
}

// MARK: - Fixtures

private func spokenMessage(
    id: String,
    body: String,
    isFromMe: Bool = false
) -> ChatMessage {
    ChatMessage(
        id: id,
        chatRoomID: room.id,
        sender: ChatMember(id: isFromMe ? "me" : "s1", displayName: "상대"),
        body: body,
        sentAt: Date(timeIntervalSince1970: 1_000_000),
        isFromMe: isFromMe
    )
}

private func evaluation(
    chance: InterjectionChance,
    messages: [ChatMessage],
    room: ChatRoom = room,
    roll: InterjectionRoll = .fromJudgedRun,
    answeringFrom: String? = nil
) -> ReplyEvaluationRequest {
    ReplyEvaluationRequest(
        room: room,
        policy: RoomPolicy(
            accountFingerprint: account,
            chatRoomID: room.id,
            responseMode: .automatic,
            interjectionChance: chance,
            minimumInterval: 0
        ),
        globalResponsesEnabled: true,
        accountVerified: true,
        recentMessages: messages,
        responseKeywords: ["한결"],
        interjectionRoll: roll,
        answeringFrom: answeringFrom
    )
}
