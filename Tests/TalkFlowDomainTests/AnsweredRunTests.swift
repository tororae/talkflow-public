import Foundation
import Testing
@testable import TalkFlowDomain

private let opening = Date(timeIntervalSince1970: 1_000_000)

/// The run starts where the judgement started, and everything said after it is
/// part of the same answer. This is what 뒷말 대기 produces: one reply covering a
/// thought somebody split across messages.
@Test
func aRunAnchoredEarlierCarriesEverythingSaidAfterIt() {
    let conversation = (1...4).map { runMessage(id: "m\($0)", body: "메시지 \($0)번", secondsIn: $0) }

    let run = AnsweredRun.from(conversation, startingAt: "m2")

    #expect(run.lines.map(\.messageID) == ["m2", "m3", "m4"])
    #expect(run.omittedCount == 0)
}

/// A room judging every message answers the one that arrived. Without an anchor
/// the run is that message alone, which is what the record has always said.
@Test
func aRunWithNoAnchorIsTheNewestMessageAlone() {
    let conversation = (1...3).map { runMessage(id: "m\($0)", body: "메시지 \($0)번", secondsIn: $0) }

    #expect(AnsweredRun.from(conversation, startingAt: nil).lines.map(\.messageID) == ["m3"])
}

/// An interval in an active room accumulates more than a person will read off
/// one pane. The newest survive and the count of what came off is carried, so
/// nothing is shown as a whole run that is only part of one.
@Test
func aRunTooLongForTheRecordKeepsTheNewestAndCountsWhatCameOff() {
    let conversation = (1...25).map { runMessage(id: "m\($0)", body: "메시지 \($0)번", secondsIn: $0) }

    let run = AnsweredRun.from(conversation, startingAt: "m1")

    #expect(run.lines.count == AnsweredRun.messageLimit)
    #expect(run.lines.first?.messageID == "m6")
    #expect(run.lines.last?.messageID == "m25")
    #expect(run.omittedCount == 5)
}

/// Counting messages alone would let one pasted block outweigh a day of
/// conversation, so length cuts in first when the messages are long.
@Test
func aRunOfLongMessagesIsCutByLengthBeforeItReachesTheCount() {
    let conversation = (1...10).map {
        runMessage(id: "m\($0)", body: String(repeating: "가", count: 400), secondsIn: $0)
    }

    let run = AnsweredRun.from(conversation, startingAt: "m1")

    #expect(run.lines.count < AnsweredRun.messageLimit)
    #expect(run.lines.map(\.body.count).reduce(0, +) <= AnsweredRun.characterBudget)
    #expect(run.lines.last?.messageID == "m10")
    #expect(run.omittedCount == 10 - run.lines.count)
}

/// The prompt window drops its oldest for length, and the run's opening can go
/// with them. Everything still held is inside the run, so a long batch must not
/// collapse to one line because its first message scrolled off.
@Test
func anAnchorOlderThanWhatIsLeftKeepsEverythingStillHeld() {
    let conversation = (3...6).map { runMessage(id: "m\($0)", body: "메시지 \($0)번", secondsIn: $0) }

    let run = AnsweredRun.from(conversation, startingAt: "m1")

    #expect(run.lines.map(\.messageID) == ["m3", "m4", "m5", "m6"])
}

/// KakaoTalk keeps the word 사진 in a photo row and a system notice's JSON in an
/// attachment row. A batch carries both, and neither belongs in front of a
/// person as the raw column.
@Test
func picturesAndNoticesInARunReadAsThemselvesRatherThanTheirRawRows() {
    let conversation = [
        runMessage(id: "m1", body: "사진", kind: .photo, secondsIn: 1),
        runMessage(id: "m2", body: #"{"feedType":4}"#, kind: .attachment, secondsIn: 2),
        runMessage(id: "m3", body: "이거 어때요?", secondsIn: 3)
    ]

    let run = AnsweredRun.from(conversation, startingAt: "m1")

    #expect(run.lines.map(\.body) == ["(사진)", "(사진 또는 이모티콘)", "이거 어때요?"])
}

/// A batch spans both sides of the conversation. The account's own messages are
/// named the way the prompt names them, because a display name means nothing to
/// the person reading their own record.
@Test
func myOwnMessagesInARunAreNamedAsMine() {
    let conversation = [
        runMessage(id: "m1", body: "알겠습니다", isFromMe: true, secondsIn: 1),
        runMessage(id: "m2", body: "그럼 내일 봬요", secondsIn: 2)
    ]

    let run = AnsweredRun.from(conversation, startingAt: "m1")

    #expect(run.lines.map(\.senderName) == ["나", "지수"])
}

/// The record is read long after the archive it came from is pruned, so it goes
/// to disk as a value rather than as ids to look up later.
@Test
func aRunRoundTripsThroughItsEncodedForm() throws {
    let run = AnsweredRun.from(
        (1...3).map { runMessage(id: "m\($0)", body: "메시지 \($0)번", secondsIn: $0) },
        startingAt: "m1"
    )

    let decoded = try JSONDecoder().decode(AnsweredRun.self, from: JSONEncoder().encode(run))

    #expect(decoded == run)
}

// MARK: - Fixtures

private func runMessage(
    id: String,
    senderID: String = "s1",
    body: String,
    kind: ChatMessage.Kind = .text,
    isFromMe: Bool = false,
    secondsIn: Int
) -> ChatMessage {
    ChatMessage(
        id: id,
        chatRoomID: "room",
        sender: ChatMember(id: senderID, displayName: "지수"),
        body: body,
        sentAt: opening.addingTimeInterval(Double(secondsIn)),
        kind: kind,
        isFromMe: isFromMe
    )
}
