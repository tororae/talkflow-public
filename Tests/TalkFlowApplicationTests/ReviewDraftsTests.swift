import Foundation
import Testing
import TalkFlowDomain
@testable import TalkFlowApplication

private func draft(
    id: Int64 = 1,
    fingerprint: String = testAccount.fingerprint,
    text: String? = "네 좋아요"
) -> AgentAction {
    AgentAction(
        id: id,
        accountFingerprint: fingerprint,
        chatRoomID: testDirectRoom.id,
        chatRoomName: testDirectRoom.displayName,
        kind: .drafted,
        triggerMessageID: "m1",
        replyText: text,
        detail: "초안을 만들었습니다."
    )
}

private func makeReview(
    log: FakeActionLog = FakeActionLog(),
    sender: FakeMessageSender = FakeMessageSender(),
    status: KakaoConnectionStatus = .connected(account: testAccount),
    sendStore: FakeSendStore? = nil
) -> ReviewDrafts {
    ReviewDrafts(
        actionLog: log,
        settingsStore: FakeSettingsStore(),
        connection: FakeKakaoConnection(status: status),
        sender: sender,
        sendStore: sendStore
    )
}

/// The queue's copy of the same draft: one message, two places it lives.
private func queuedCopyOfTheDraft() -> PendingSend {
    PendingSend(
        id: 1,
        accountFingerprint: testAccount.fingerprint,
        chatRoomID: testDirectRoom.id,
        chatRoomName: testDirectRoom.displayName,
        triggerMessageID: "m1",
        text: "네 좋아요",
        eligibleAt: Date(timeIntervalSince1970: 1_000_000)
    )
}

/// Observed on a real machine: a draft dismissed at 10:11:46 was delivered by
/// the queue at 10:13:43. 무시 wrote a timeline row and nothing else, so the
/// entry the queue was holding stayed live and went out as soon as its
/// conditions were met — the app sending a message its owner had declined.
@Test
func dismissingADraftAlsoCancelsTheCopyTheQueueIsHolding() async throws {
    let sendStore = FakeSendStore([queuedCopyOfTheDraft()])
    let review = makeReview(sendStore: sendStore)

    try await review.dismiss(draft())

    #expect(try await sendStore.waiting().isEmpty)
    #expect(await sendStore.resolutions.map(\.state) == [.cancelled])
}

/// The same hole on the other button. A draft delivered by hand that stayed in
/// the queue would be delivered again the moment the queue's conditions were
/// met, and the second copy is not recallable either.
@Test
func sendingADraftByHandTakesItOutOfTheQueueToo() async throws {
    let sendStore = FakeSendStore([queuedCopyOfTheDraft()])
    let review = makeReview(sendStore: sendStore)

    try await review.send(draft())

    #expect(try await sendStore.waiting().isEmpty)
    #expect(await sendStore.resolutions.map(\.state) == [.sent])
}

/// A draft-only room has no queue entry to withdraw, and a decision about one
/// must not fail for the absence of the other.
@Test
func decidingADraftThatWasNeverQueuedStillWorks() async throws {
    let log = FakeActionLog(existing: [draft()])
    let review = makeReview(log: log, sendStore: FakeSendStore())

    try await review.dismiss(draft())

    #expect(try await review.pending().isEmpty)
}

@Test
func sendingADraftDeliversItAndRecordsTheSend() async throws {
    let log = FakeActionLog()
    let sender = FakeMessageSender()
    let review = makeReview(log: log, sender: sender)

    try await review.send(draft())

    #expect(await sender.sent.map(\.text) == ["네 좋아요"])
    #expect(await log.recorded.last?.kind == .sent)
    #expect(await log.recorded.last?.detail.contains("검토 후") == true)
}

@Test
func anEditedDraftSendsTheEditedTextAndSaysSo() async throws {
    let log = FakeActionLog()
    let sender = FakeMessageSender()
    let review = makeReview(log: log, sender: sender)

    try await review.send(draft(), text: "고쳐서 보냄")

    #expect(await sender.sent.map(\.text) == ["고쳐서 보냄"])
    #expect(await log.recorded.last?.replyText == "고쳐서 보냄")
    #expect(await log.recorded.last?.detail.contains("수정 후") == true)
}

/// A draft written for one account must never leave from another. The idle and
/// settling rules do not apply to a manual send — the user is present — but this
/// one still does.
@Test
func aDraftFromAnotherAccountIsRefused() async {
    let sender = FakeMessageSender()
    let review = makeReview(sender: sender)

    await #expect(throws: ReviewError.accountChanged) {
        try await review.send(draft(fingerprint: "katok-someone-else"))
    }
    #expect(await sender.sent.isEmpty)
}

@Test
func anUnverifiedConnectionRefusesToSend() async {
    let sender = FakeMessageSender()
    let review = makeReview(sender: sender, status: .unavailable(reason: "확인 실패"))

    await #expect(throws: ReviewError.accountUnavailable) {
        try await review.send(draft())
    }
    #expect(await sender.sent.isEmpty)
}

@Test
func anEmptyDraftIsNotSent() async {
    let sender = FakeMessageSender()
    let review = makeReview(sender: sender)

    await #expect(throws: ReviewError.emptyDraft) {
        try await review.send(draft(text: "   \n  "))
    }
    #expect(await sender.sent.isEmpty)
}

@Test
func dismissingADraftDoesNotSendAnything() async throws {
    let log = FakeActionLog(existing: [draft()])
    let sender = FakeMessageSender()
    let review = makeReview(log: log, sender: sender)

    try await review.dismiss(draft())

    #expect(await sender.sent.isEmpty)
    #expect(try await review.pending().isEmpty)
}

/// A failure shown only in the window the user is looking at disappears the
/// moment they look away, which is how a send that never happened came to look
/// exactly like one that was never attempted.
@Test
func aFailedSendIsWrittenDownRatherThanOnlyShown() async throws {
    let log = FakeActionLog(existing: [draft()])
    let review = makeReview(
        log: log,
        sender: FakeMessageSender(
            failure: MessageSendFailure(message: "카카오톡이 Enter를 받지 않았습니다.", isRetryable: true)
        )
    )

    await #expect(throws: MessageSendFailure.self) {
        try await review.send(draft())
    }

    #expect(await log.recorded.last?.kind == .failed)
    #expect(await log.recorded.last?.detail == "카카오톡이 Enter를 받지 않았습니다.")
}

/// Including the checks that refuse before anything leaves: from the timeline's
/// side "it did not send" is one question, and it should have one answer.
@Test
func aSendRefusedBeforeItLeavesIsRecordedToo() async {
    let log = FakeActionLog(existing: [draft()])
    let review = makeReview(log: log, status: .unavailable(reason: "확인 실패"))

    await #expect(throws: ReviewError.accountUnavailable) {
        try await review.send(draft())
    }

    #expect(await log.recorded.last?.kind == .failed)
}

/// A retryable failure must not consume the draft: the reasons a send fails are
/// states of the screen that pass, and the user should be able to press again.
@Test
func aDraftSurvivesAFailedSend() async throws {
    let log = FakeActionLog(existing: [draft()])
    let review = makeReview(
        log: log,
        sender: FakeMessageSender(failure: MessageSendFailure(message: "실패", isRetryable: true))
    )

    await #expect(throws: MessageSendFailure.self) {
        try await review.send(draft())
    }

    #expect(try await review.pending().contains { $0.id == 1 })
}
