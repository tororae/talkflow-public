import Foundation
import Testing
@testable import TalkFlowDomain

private let account = "katok-count"
private let directRoom = ChatRoom(id: "room-d", displayName: "가족", kind: .direct)
private let groupRoom = ChatRoom(id: "room-g", displayName: "프로젝트 팀", kind: .group)
private let engine = ResponsePolicyEngine()
private let now = Date(timeIntervalSince1970: 1_000_000)

/// The whole point of counting conversation instead of time. A room that talks
/// twice a day and a room that talks thirty times an hour get the same amount of
/// conversation out of the same number, which is what a stretch of minutes cannot
/// do in both.
@Test
func aCountedCycleHoldsUntilItsNthMessageArrives() {
    let start = now.addingTimeInterval(-3600)

    let short = engine.evaluate(
        counted(messages: others(4, from: start), lastJudgementAt: start)
    )
    let full = engine.evaluate(
        counted(messages: others(5, from: start), lastJudgementAt: start)
    )

    #expect(short == .hold(reason: .collecting(remaining: 1)))
    #expect(full == .ask(trigger: .directQuestion, triggerMessageID: "m5"))
}

/// And when it does fill up it answers everything it accumulated, not whatever
/// happened to be last. A call in the first message of the cycle is still a call
/// five messages later — the same promise the timed cycle makes, because it is
/// the same accumulation.
@Test
func theCountEndingReleasesEveryMessageItCollected() {
    let start = now.addingTimeInterval(-3600)
    var messages = others(5, from: start)
    messages[0] = message(id: "m1", body: "한결 이거 확인 부탁해요", sentAt: start.addingTimeInterval(60))

    let outcome = engine.evaluate(
        counted(
            room: groupRoom,
            messages: messages,
            lastJudgementAt: start,
            mode: .mentionOnly
        )
    )

    #expect(outcome == .ask(trigger: .mention, triggerMessageID: "m5"))
}

/// **Other people's messages only.** Six of the nine below are mine, so a cycle
/// counting everything would have fired twice over; counting what the room said
/// to us, it is still two short. The user typing is the user handling the room
/// themselves, and a reply TalkFlow sent comes back through the archive as ours
/// too — either one counted would let the room talk itself into answering sooner.
@Test
func myOwnMessagesDoNotBringTheNextAnswerCloser() {
    let start = now.addingTimeInterval(-3600)
    let mine = (1...6).map {
        message(id: "m\($0)", body: "그건 내가 할게", sentAt: start.addingTimeInterval(Double($0) * 60), isFromMe: true)
    }
    let theirs = (7...9).map {
        message(id: "m\($0)", body: "이건 어떻게 할까요", sentAt: start.addingTimeInterval(Double($0) * 60))
    }

    let outcome = engine.evaluate(counted(messages: mine + theirs, lastJudgementAt: start))

    #expect(outcome == .hold(reason: .collecting(remaining: 2)))
}

/// The same trap the timed cycle is built around. The pipeline re-reads a room on
/// every sync, and a count drawn fresh at each of those would collapse the range
/// to its shortest end. The roll below answers 0.5 for the cycle's own start and
/// 1.0 for anything else, so a count taken from the clock would be 15 and these
/// holds would read 6 rather than 1.
@Test
func aCountedRangeIsDrawnFromTheCycleStartAndNotAgainWhileItRuns() {
    let start = now.addingTimeInterval(-3600)
    let messages = others(9, from: start)
    let range = JudgementInterval(measure: .messages, shortest: 5, longest: 15)

    let early = engine.evaluate(
        counted(messages: messages, lastJudgementAt: start, interval: range, now: now)
    )
    let later = engine.evaluate(
        counted(
            messages: messages,
            lastJudgementAt: start,
            interval: range,
            now: now.addingTimeInterval(900)
        )
    )

    #expect(early == .hold(reason: .collecting(remaining: 1)))
    #expect(later == .hold(reason: .collecting(remaining: 1)))
}

/// A room that answers on exactly every tenth message is readable as a machine
/// from the pattern alone, so the count is spread the way the wait is.
@Test
func aCountedRangeVariesBetweenCyclesAndStaysInsideItsEnds() {
    let range = JudgementInterval(measure: .messages, shortest: 5, longest: 15)

    let drawn = (0..<20).compactMap { step -> Int? in
        guard case let .messages(count) = range.target(
            startingAt: now.addingTimeInterval(Double(step) * 137)
        ) else {
            return nil
        }
        return count
    }

    #expect(drawn.count == 20)
    #expect(Set(drawn).count > 1)
    #expect(drawn.allSatisfy { (5...15).contains($0) })
}

/// A room nobody has asked anything yet has no cycle to wait out, whichever way
/// it counts. Holding its first message would be a wait with no beginning.
@Test
func aRoomWithNothingRecordedJudgesTheNextMessage() {
    let outcome = engine.evaluate(
        counted(messages: others(1, from: now.addingTimeInterval(-600)), lastJudgementAt: nil)
    )

    #expect(outcome == .ask(trigger: .directQuestion, triggerMessageID: "m1"))
}

/// The hold has to say what it is counting. "2초 남았습니다" under a cycle set to
/// 5개 is the screen describing a setting the room does not have.
@Test
func theHoldCountsInWhateverTheCycleCounts() {
    #expect(ReplyHoldReason.collecting(remaining: 2).explanation.contains("2개"))
    #expect(ReplyHoldReason.batching(remaining: 2).explanation.contains("2초"))
}

/// What the room screen and the setting card call this cadence.
@Test
func aCountedCadenceReadsAsItselfOnScreen() {
    #expect(JudgementInterval(fixed: 10, measure: .messages).summary == "10개마다")
    #expect(
        JudgementInterval(measure: .messages, shortest: 5, longest: 15).summary == "5개~15개마다"
    )
}

/// 즉시 keeps no numbers, so it may not keep a unit either. Two rooms that both
/// judge every message have to compare equal however their fields were last left.
@Test
func immediateKeepsNoUnitOfItsOwn() {
    #expect(JudgementInterval(fixed: 0, measure: .messages) == .immediate)
    #expect(JudgementInterval(measure: .messages, shortest: 0, longest: 0).countsMessages == false)
    #expect(JudgementInterval.immediate.target(startingAt: now) == nil)
}

/// The count is typed in the same fields as the wait, with bounds of its own. One
/// message would be 즉시 said a second way, and the ceiling is what one model call
/// can still see — a target above the context window could sit unreachable while
/// the room accumulated for ever.
@Test
func aTypedCountIsBoundedAtBothEnds() throws {
    let input = JudgementIntervalInput.judgement
    let bounds = try #require(input.messages)
    let floor = Int(bounds.lowest)
    let ceiling = Int(bounds.highest)

    #expect(input.interval(shortest: "10", longest: "", unit: .messages)
        == .success(JudgementInterval(fixed: 10, measure: .messages)))
    #expect(input.interval(shortest: "5", longest: "15", unit: .messages)
        == .success(JudgementInterval(measure: .messages, shortest: 5, longest: 15)))
    #expect(input.interval(shortest: "\(floor - 1)", longest: "", unit: .messages) == .failure(.tooShort))
    #expect(input.interval(shortest: "\(ceiling + 1)", longest: "", unit: .messages) == .failure(.tooLong))
    #expect(input.interval(shortest: "15", longest: "5", unit: .messages) == .failure(.inverted))
    #expect(ceiling < ConversationWindow.messageLimit)
}

/// Which unit a stored cycle comes back in, and what the field says beside a
/// number it would not take. A count refused for being too small must not quote
/// the clock's floor at somebody who is typing messages.
@Test
func theFieldsReadACountBackAsACount() {
    let input = JudgementIntervalInput.judgement
    let range = JudgementInterval(measure: .messages, shortest: 5, longest: 15)

    #expect(JudgementIntervalInput.unit(for: range) == .messages)
    #expect(input.units.contains(.messages))
    #expect(JudgementIntervalInput.conversationOpener.units.contains(.messages) == false)
    #expect(input.explanation(.tooShort, in: .messages).contains("2개"))
    #expect(input.explanation(.tooShort, in: .minutes).contains("5초"))
    #expect(input.typed(range.longest, in: .messages) == "15")
}

// MARK: - Fixtures

private func message(
    id: String,
    body: String,
    sentAt: Date,
    isFromMe: Bool = false
) -> ChatMessage {
    ChatMessage(
        id: id,
        chatRoomID: directRoom.id,
        sender: ChatMember(id: isFromMe ? "me" : "s1", displayName: isFromMe ? "나" : "상대"),
        body: body,
        sentAt: sentAt,
        kind: .text,
        isFromMe: isFromMe
    )
}

/// A run of messages from other people, a minute apart, all after the cycle began.
private func others(_ count: Int, from start: Date) -> [ChatMessage] {
    (1...count).map { step in
        message(id: "m\(step)", body: "이건 어떻게 할까요", sentAt: start.addingTimeInterval(Double(step) * 60))
    }
}

/// Halfway up the range for the cycle's own start, and the top of it for any
/// other instant — so a count anchored on the wrong thing comes out different
/// rather than merely coming out the same.
private func counted(
    room: ChatRoom = directRoom,
    messages: [ChatMessage],
    lastJudgementAt: Date?,
    interval: JudgementInterval = JudgementInterval(fixed: 5, measure: .messages),
    mode: ResponseMode = .automatic,
    now: Date = now
) -> ReplyEvaluationRequest {
    ReplyEvaluationRequest(
        room: room,
        policy: RoomPolicy(
            accountFingerprint: account,
            chatRoomID: room.id,
            responseMode: mode,
            minimumInterval: 0,
            judgementInterval: interval
        ),
        globalResponsesEnabled: true,
        accountVerified: true,
        recentMessages: messages,
        lastJudgementAt: lastJudgementAt,
        responseKeywords: ["한결"],
        now: now,
        judgementRoll: JudgementRoll { $0 == lastJudgementAt ? 0.5 : 1 }
    )
}
