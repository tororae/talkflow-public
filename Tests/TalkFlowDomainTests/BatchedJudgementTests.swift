import Foundation
import Testing
@testable import TalkFlowDomain

private let account = "katok-batch"
private let groupRoom = ChatRoom(id: "room-g", displayName: "프로젝트 팀", kind: .group)
private let directRoom = ChatRoom(id: "room-d", displayName: "가족", kind: .direct)
private let engine = ResponsePolicyEngine()
private let now = Date(timeIntervalSince1970: 1_000_000)

/// A room that judges in batches says nothing until its interval is up, and the
/// hold names the wait rather than leaving the room looking broken.
@Test
func aBatchingRoomHoldsEveryMessageUntilItsIntervalIsUp() {
    let outcome = engine.evaluate(
        batched(
            room: directRoom,
            messages: [batchMessage(id: "m1", body: "내일 시간 돼?", secondsAgo: 30)],
            lastJudgementAt: now.addingTimeInterval(-60)
        )
    )

    #expect(outcome == .hold(reason: .batching(remaining: 540)))
}

/// The interval and the cooldown both bound how often a room speaks, so only one
/// is ever in force. Applying both would make a batching room wait out the
/// interval and then a cooldown nobody asked it to observe.
@Test
func theBatchIntervalStandsInForTheCooldownRatherThanStackingWithIt() {
    let outcome = engine.evaluate(
        batched(
            room: directRoom,
            messages: [batchMessage(id: "m1", body: "내일 시간 돼?", secondsAgo: 30)],
            lastReplyAt: now.addingTimeInterval(-60),
            lastJudgementAt: now.addingTimeInterval(-700),
            minimumInterval: 3600
        )
    )

    #expect(outcome == .ask(trigger: .directQuestion, triggerMessageID: "m1"))
}

/// The point of accumulating: a call that arrived early in the interval is still
/// a call when the interval ends. Judging only the newest message would drop it,
/// and a mention-only room would batch its way into never answering a mention.
@Test
func aBatchAnswersACallThatArrivedEarlierInTheInterval() {
    let outcome = engine.evaluate(
        batched(
            room: groupRoom,
            mode: .mentionOnly,
            messages: [
                batchMessage(id: "m1", body: "한결 이거 확인 부탁해요", secondsAgo: 500),
                batchMessage(id: "m2", senderID: "s2", body: "저도 궁금하네요", secondsAgo: 400)
            ],
            lastJudgementAt: now.addingTimeInterval(-700)
        )
    )

    #expect(outcome == .ask(trigger: .mention, triggerMessageID: "m2"))
}

/// Only what arrived since the last judgement counts. A call TalkFlow already
/// answered is not a reason to answer again on the next interval.
@Test
func aBatchIgnoresCallsItAlreadyJudged() {
    let outcome = engine.evaluate(
        batched(
            room: groupRoom,
            mode: .mentionOnly,
            messages: [
                batchMessage(id: "m1", body: "한결 이거 확인 부탁해요", secondsAgo: 900),
                batchMessage(id: "m2", senderID: "s2", body: "저도 궁금하네요", secondsAgo: 400)
            ],
            lastJudgementAt: now.addingTimeInterval(-800)
        )
    )

    #expect(outcome == .hold(reason: .notAddressed))
}

/// A room left on 즉시 is unaffected by any of this: the cooldown is still the
/// only thing pacing it.
@Test
func aRoomJudgingEveryMessageStillObeysItsCooldown() {
    let outcome = engine.evaluate(
        batched(
            room: directRoom,
            messages: [batchMessage(id: "m1", body: "또 물어봐도 돼?", secondsAgo: 10)],
            lastReplyAt: now.addingTimeInterval(-120),
            lastJudgementAt: now.addingTimeInterval(-120),
            minimumInterval: 300,
            judgementInterval: .immediate
        )
    )

    #expect(outcome == .hold(reason: .cooldown(remaining: 180)))
}

// MARK: - Fixtures

private func batchMessage(
    id: String,
    senderID: String = "s1",
    body: String,
    secondsAgo: Int
) -> ChatMessage {
    ChatMessage(
        id: id,
        chatRoomID: "room",
        sender: ChatMember(id: senderID, displayName: "상대"),
        body: body,
        sentAt: now.addingTimeInterval(-Double(secondsAgo))
    )
}

private func batched(
    room: ChatRoom,
    mode: ResponseMode = .automatic,
    messages: [ChatMessage],
    lastReplyAt: Date? = nil,
    lastJudgementAt: Date?,
    minimumInterval: TimeInterval = 0,
    judgementInterval: JudgementInterval = JudgementInterval(fixed: 600)
) -> ReplyEvaluationRequest {
    ReplyEvaluationRequest(
        room: room,
        policy: RoomPolicy(
            accountFingerprint: account,
            chatRoomID: room.id,
            responseMode: mode,
            minimumInterval: minimumInterval,
            judgementInterval: judgementInterval
        ),
        globalResponsesEnabled: true,
        accountVerified: true,
        recentMessages: messages,
        lastReplyAt: lastReplyAt,
        lastJudgementAt: lastJudgementAt,
        responseKeywords: ["한결"],
        now: now
    )
}
