import Foundation
import Testing
@testable import TalkFlowDomain

private let account = "katok-interval"
private let room = ChatRoom(id: "room-d", displayName: "가족", kind: .direct)
private let engine = ResponsePolicyEngine()
private let now = Date(timeIntervalSince1970: 1_000_000)

/// A room answering at exactly the same interval every time is a machine anyone
/// can spot from the clock alone, so a range spreads the cadence.
@Test
func aRangeWaitsADifferentLengthOnDifferentCycles() {
    let interval = JudgementInterval(shortest: 10, longest: 300)

    let waits = (0..<20).compactMap { step in
        interval.target(startingAt: now.addingTimeInterval(Double(step) * 137))?.wait
    }

    #expect(waits.count == 20)
    #expect(Set(waits).count > 1)
    #expect(waits.allSatisfy { $0 >= 10 && $0 <= 300 })
}

/// The trap this feature is built around. The pipeline re-evaluates a room on
/// every sync, so a wait drawn fresh at each of those would collapse the range to
/// its shortest end — whichever draw lands low fires, and the long ones never get
/// to expire. Drawing from the cycle's start makes that impossible rather than
/// merely unlikely.
@Test
func theWaitIsDrawnOnceForACycleAndNotAgainWhileItRuns() {
    let interval = JudgementInterval(shortest: 10, longest: 600)
    let start = now.addingTimeInterval(-30)

    let first = interval.target(startingAt: start)
    let again = interval.target(startingAt: start)

    #expect(first == again)
}

/// What keeps that true through the engine: the draw is handed the instant the
/// cycle began, never the instant it is being asked. The roll below answers 0.5
/// for the cycle's start and 1.0 for anything else, so an engine reading the
/// clock instead would wait the full 600 and the numbers here would be 570 and
/// 555 rather than a countdown from 330.
@Test
func theEngineDrawsFromTheCycleStartRatherThanFromTheClock() {
    let start = now.addingTimeInterval(-30)
    let messages = [intervalMessage(id: "m1", body: "내일 시간 돼?", sentAt: now.addingTimeInterval(-20))]

    let early = engine.evaluate(batched(messages: messages, lastJudgementAt: start, now: now))
    let later = engine.evaluate(
        batched(messages: messages, lastJudgementAt: start, now: now.addingTimeInterval(15))
    )

    #expect(early == .hold(reason: .batching(remaining: 300)))
    #expect(later == .hold(reason: .batching(remaining: 285)))
}

/// The deadline is anchored to the cycle's start, so messages arriving during it
/// shorten the remaining wait rather than extending it. Pushing the deadline out
/// on each new message is how the old settling delay never reached the end of its
/// own wait in a room where somebody keeps typing.
@Test
func messagesArrivingDuringACycleDoNotPushItsDeadlineOut() {
    let start = now.addingTimeInterval(-200)
    let quiet = [intervalMessage(id: "m1", body: "이거 봤어?", sentAt: now.addingTimeInterval(-190))]
    let busy = quiet + (2...9).map {
        intervalMessage(id: "m\($0)", body: "그리고 하나 더", sentAt: now.addingTimeInterval(-10))
    }

    let afterOne = engine.evaluate(batched(messages: quiet, lastJudgementAt: start, now: now))
    let afterMany = engine.evaluate(batched(messages: busy, lastJudgementAt: start, now: now))

    #expect(afterOne == .hold(reason: .batching(remaining: 130)))
    #expect(afterMany == .hold(reason: .batching(remaining: 130)))
}

/// And when it does run out, the room judges instead of waiting again — with
/// everything it accumulated, not just whatever landed last.
@Test
func theCycleEndingReleasesEverythingItAccumulated() {
    let start = now.addingTimeInterval(-400)
    let outcome = engine.evaluate(
        batched(
            messages: [
                intervalMessage(id: "m1", body: "먼저 온 말", sentAt: now.addingTimeInterval(-390)),
                intervalMessage(id: "m2", body: "그래서 어떻게 할까", sentAt: now.addingTimeInterval(-20))
            ],
            lastJudgementAt: start,
            now: now
        )
    )

    #expect(outcome == .ask(trigger: .directQuestion, triggerMessageID: "m2"))
}

/// Equal ends are a fixed interval, which is what most rooms want and what every
/// room had before ranges existed.
@Test
func equalEndsWaitTheSameLengthEveryCycle() {
    let interval = JudgementInterval(fixed: 300)

    let waits = (0..<10).compactMap {
        interval.target(startingAt: now.addingTimeInterval(Double($0) * 61))?.wait
    }

    #expect(Set(waits) == [300])
}

/// A range cannot exist inverted: the value raises the top rather than carrying a
/// pair the engine would have to check every time it reads one.
@Test
func aRangeCannotBeStoredWithItsEndsTheWrongWayRound() {
    let interval = JudgementInterval(shortest: 300, longest: 10)

    #expect(interval.longest == 300)
    #expect(interval.isFixed)
}

/// Typed by somebody who meant it, though, an inverted range is refused rather
/// than quietly straightened out — silently swapping the numbers would tell them
/// they typed something they did not.
@Test
func typingTheEndsTheWrongWayRoundIsRefused() {
    let outcome = JudgementIntervalInput.judgement.interval(shortest: "5", longest: "1", unit: .minutes)

    #expect(outcome == .failure(.inverted))
}

@Test
func aTypedRangeBecomesSecondsInTheUnitItWasTypedIn() {
    let seconds = JudgementIntervalInput.judgement.interval(shortest: "10", longest: "300", unit: .seconds)
    let minutes = JudgementIntervalInput.judgement.interval(shortest: "3", longest: "5", unit: .minutes)

    #expect(seconds == .success(JudgementInterval(shortest: 10, longest: 300)))
    #expect(minutes == .success(JudgementInterval(shortest: 180, longest: 300)))
}

/// One number is the common case, so the second field may be left alone.
@Test
func anEmptyTopEndMeansAFixedInterval() {
    let outcome = JudgementIntervalInput.judgement.interval(shortest: "7", longest: "  ", unit: .minutes)

    #expect(outcome == .success(JudgementInterval(fixed: 420)))
}

/// Zero is not 즉시. 즉시 is its own choice, and letting an empty or zero field
/// mean it would make "no interval" and "not filled in yet" the same value.
@Test
func zeroAndNegativeAndNonsenseAreAllRefused() {
    #expect(JudgementIntervalInput.judgement.interval(shortest: "0", longest: "", unit: .minutes) == .failure(.tooShort))
    #expect(JudgementIntervalInput.judgement.interval(shortest: "-3", longest: "", unit: .minutes) == .failure(.tooShort))
    #expect(JudgementIntervalInput.judgement.interval(shortest: "", longest: "", unit: .minutes) == .failure(.notANumber))
    #expect(JudgementIntervalInput.judgement.interval(shortest: "다섯", longest: "", unit: .minutes) == .failure(.notANumber))
    #expect(JudgementIntervalInput.judgement.interval(shortest: "4", longest: "", unit: .seconds) == .failure(.tooShort))
}

/// The ceiling is where the setting stops doing what it says: past it the room
/// answers a conversation that has moved on, and the batch gets trimmed anyway.
@Test
func theCeilingHoldsOnBothEndsAndOnNumbersTooBigToBeOne() {
    let ceiling = Int(JudgementIntervalInput.judgement.time.highest / 60)

    #expect(JudgementIntervalInput.judgement.interval(shortest: "\(ceiling)", longest: "", unit: .minutes)
        == .success(JudgementInterval(fixed: JudgementIntervalInput.judgement.time.highest)))
    #expect(JudgementIntervalInput.judgement.interval(shortest: "\(ceiling + 1)", longest: "", unit: .minutes)
        == .failure(.tooLong))
    #expect(JudgementIntervalInput.judgement.interval(shortest: "5", longest: "\(ceiling + 1)", unit: .minutes)
        == .failure(.tooLong))
    #expect(JudgementIntervalInput.judgement.interval(shortest: "999999999999999999999", longest: "", unit: .minutes)
        == .failure(.tooLong))
}

/// The field has to show a stored range without rounding half of it away, and a
/// room on 즉시 has no number of its own to show.
@Test
func theFieldsChooseAUnitThatKeepsTheStoredNumbersWhole() {
    let mixed = JudgementInterval(shortest: 10, longest: 300)
    let whole = JudgementInterval(shortest: 180, longest: 600)

    #expect(JudgementIntervalInput.unit(for: mixed) == .seconds)
    #expect(JudgementIntervalInput.unit(for: whole) == .minutes)
    #expect(JudgementIntervalInput.judgement.typed(mixed.longest, in: .seconds) == "300")
    #expect(JudgementIntervalInput.judgement.typed(whole.shortest, in: .minutes) == "3")
    #expect(JudgementIntervalInput.judgement.typed(0, in: .minutes) == "5")
}

/// What the room screen and the setting cards call a cadence, in one place so
/// they cannot call the same one two things.
@Test
func aCadenceReadsAsItselfOnScreen() {
    #expect(JudgementInterval.immediate.summary == "즉시")
    #expect(JudgementInterval(fixed: 300).summary == "5분마다")
    #expect(JudgementInterval(shortest: 10, longest: 300).summary == "10초~5분마다")
}

// MARK: - Fixtures

private func intervalMessage(id: String, body: String, sentAt: Date) -> ChatMessage {
    ChatMessage(
        id: id,
        chatRoomID: room.id,
        sender: ChatMember(id: "s1", displayName: "상대"),
        body: body,
        sentAt: sentAt
    )
}

/// Halfway up the range for the cycle's own start, and the top of it for any
/// other instant — so a wait anchored on the wrong thing reads differently
/// instead of merely reading the same.
private func batched(
    messages: [ChatMessage],
    lastJudgementAt: Date,
    now: Date
) -> ReplyEvaluationRequest {
    ReplyEvaluationRequest(
        room: room,
        policy: RoomPolicy(
            accountFingerprint: account,
            chatRoomID: room.id,
            responseMode: .automatic,
            minimumInterval: 0,
            judgementInterval: JudgementInterval(shortest: 60, longest: 600)
        ),
        globalResponsesEnabled: true,
        accountVerified: true,
        recentMessages: messages,
        lastJudgementAt: lastJudgementAt,
        now: now,
        judgementRoll: JudgementRoll { $0 == lastJudgementAt ? 0.5 : 1 }
    )
}
