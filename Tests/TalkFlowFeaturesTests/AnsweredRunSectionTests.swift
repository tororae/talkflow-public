import Foundation
import Testing
import TalkFlowDomain
@testable import TalkFlowFeatures

private let said = Date(timeIntervalSince1970: 1_000_000)

/// The reason this exists: a reply that answers four messages has to show the
/// four, in order, or the record cannot be read back as an exchange.
@Test
func aRunOfSeveralMessagesIsShownAsTheConversationItIs() {
    let section = AnsweredRunSection.of(
        testAction(id: 1, kind: .drafted, replyText: "곧 도착해요", run: runOf(4)),
        voice: .answering
    )

    #expect(section?.title == "이 대화에 답합니다")
    #expect(section?.body == .run(runOf(4).lines))
    #expect(section?.omittedNote == nil)
}

/// The common case is still one message, and it should read exactly as it did
/// before runs existed rather than as a one-line "conversation".
@Test
func aRunOfOneMessageStillReadsAsOneMessage() {
    let drafted = testAction(id: 1, kind: .drafted, replyText: "곧 도착해요", run: runOf(1))

    #expect(AnsweredRunSection.of(drafted, voice: .answering)?.title == "이 메시지에 답합니다")
    #expect(AnsweredRunSection.of(drafted, voice: .recorded)?.title == "촉발 메시지")
}

/// The record pane shows holds as often as replies, and a hold answered nothing,
/// so it may not promise an answer over the messages it names.
@Test
func theRecordPaneNamesTheRunWithoutPromisingAnAnswer() {
    let held = testAction(id: 1, kind: .held, run: runOf(3))

    #expect(AnsweredRunSection.of(held, voice: .recorded)?.title == "판단한 대화")
}

/// A trimmed run shown as a whole one is the same misreading in a smaller size,
/// so the pane says how much it left out.
@Test
func aTrimmedRunSaysHowMuchItLeftOut() {
    let section = AnsweredRunSection.of(
        testAction(
            id: 1,
            kind: .drafted,
            replyText: "곧 도착해요",
            run: AnsweredRun(lines: runOf(20).lines, omittedCount: 6)
        ),
        voice: .answering
    )

    #expect(section?.omittedNote?.contains("6") == true)
}

/// The rows recorded before runs existed carry one trigger line and no times.
/// They have to keep reading the way they always did: a record that turns blank
/// after an upgrade loses the history the screen is for.
@Test
func anActionRecordedBeforeRunsExistedStillShowsItsTriggerLine() {
    let old = testAction(id: 1, kind: .drafted, replyText: "곧 도착해요")

    let section = AnsweredRunSection.of(old, voice: .answering)

    #expect(section?.title == "이 메시지에 답합니다")
    #expect(section?.body == .triggerOnly("지수: 언제 와?"))
    #expect(section?.omittedNote == nil)
}

/// An action with neither a run nor a trigger — a dismissal, which copies only
/// the ids forward — shows no block at all rather than an empty labelled box.
@Test
func anActionWithNothingToShowGetsNoBlock() {
    let dismissed = AgentAction(
        accountFingerprint: testAccount.fingerprint,
        chatRoomID: "room-a",
        kind: .dismissed,
        triggerMessageID: "m1",
        detail: "사용자가 초안을 무시했습니다."
    )

    #expect(AnsweredRunSection.of(dismissed, voice: .recorded) == nil)
}

// MARK: - Fixtures

private func runOf(_ count: Int) -> AnsweredRun {
    AnsweredRun(
        lines: (1...count).map {
            AnsweredRun.Line(
                messageID: "m\($0)",
                senderName: "지수",
                sentAt: said.addingTimeInterval(Double($0) * 30),
                body: "메시지 \($0)번"
            )
        }
    )
}
