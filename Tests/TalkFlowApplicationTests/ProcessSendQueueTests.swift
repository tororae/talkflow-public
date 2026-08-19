import Foundation
import Testing
import TalkFlowDomain
@testable import TalkFlowApplication

private let now = Date(timeIntervalSince1970: 1_000_000)

@Test
func aDueDraftIsDeliveredAndMarkedSent() async {
    let sendStore = FakeSendStore([queued()])
    let sender = FakeMessageSender()
    let log = FakeActionLog()
    let queue = makeQueue(sendStore: sendStore, sender: sender, log: log)

    let resolved = await queue(now: now)

    #expect(resolved.map(\.state) == [.sent])
    #expect(await sender.sent.map(\.chatRoomID) == [testDirectRoom.id])
    #expect(await sender.sent.map(\.text) == ["네 좋아요"])
    #expect(await log.recorded.first?.kind == .sent)
}

@Test
func aDraftStillSettlingStaysQueuedAndIsNotSent() async throws {
    let sendStore = FakeSendStore([queued(eligibleAt: now.addingTimeInterval(30))])
    let sender = FakeMessageSender()
    let queue = makeQueue(sendStore: sendStore, sender: sender)

    #expect(await queue(now: now).isEmpty)
    #expect(await sender.sent.isEmpty)
    #expect(try await sendStore.waiting().count == 1)
}

@Test
func nothingGoesOutWhileTheUserIsTyping() async {
    let sender = FakeMessageSender()
    let queue = makeQueue(
        sendStore: FakeSendStore([queued()]),
        sender: sender,
        activity: FixedActivityMonitor(idleSeconds: 1)
    )

    #expect(await queue(now: now).isEmpty)
    #expect(await sender.sent.isEmpty)
}

@Test
func theEmergencyStopCancelsDraftsThatWereAlreadyQueued() async throws {
    let sendStore = FakeSendStore([queued()])
    let sender = FakeMessageSender()
    let queue = makeQueue(
        sendStore: sendStore,
        sender: sender,
        settings: FakeSettingsStore(enabled: false)
    )

    #expect(await queue(now: now).map(\.state) == [.cancelled])
    #expect(await sender.sent.isEmpty)
    #expect(try await sendStore.waiting().isEmpty)
}

@Test
func acceptingTheUsePolicyIsRequiredBeforeAnythingIsSent() async {
    let sender = FakeMessageSender()
    let queue = makeQueue(
        sendStore: FakeSendStore([queued()]),
        sender: sender,
        settings: FakeSettingsStore(usePolicyAccepted: false)
    )

    #expect(await queue(now: now).isEmpty)
    #expect(await sender.sent.isEmpty)
}

/// The reply answers s1 and s1 has carried on. It goes out anyway.
///
/// The queue no longer withdraws a draft for this. It used to, and the room it
/// was meant to protect is the room it broke: drafting takes about eight seconds,
/// somebody mid-conversation speaks inside that, the draft was dropped, the next
/// sync drafted again, and the loop had no end that did not involve the person
/// falling silent. 113 drafts died that way in three days. Whether more was
/// coming is the model's call now, made before anything is queued.
@Test
func theAnsweredPersonCarryingOnNoLongerCancelsTheDraft() async {
    let sender = FakeMessageSender()
    let queue = makeQueue(
        sendStore: FakeSendStore([queued(triggerSenderID: "s1")]),
        sender: sender,
        messages: [
            testMessage(id: "m1", body: "내일 시간 돼?"),
            testMessage(id: "m2", body: "아 아니다 모레가 낫겠다")
        ]
    )

    let resolved = await queue(now: now)

    #expect(resolved.map(\.state) == [.sent])
    #expect(await sender.sent.map(\.text) == ["네 좋아요"])
}

/// Somebody else speaking is a group chat, not a stale draft. Reading it as
/// staleness cancelled fifty eight percent of one room's replies: a model call
/// takes about ten seconds and in a busy room someone speaks inside it nearly
/// every time.
@Test
func adifferentPersonTalkingDoesNotStopTheReply() async {
    let sender = FakeMessageSender()
    let queue = makeQueue(
        sendStore: FakeSendStore([queued(triggerSenderID: "s1")]),
        sender: sender,
        messages: [
            testMessage(id: "m1", body: "내일 시간 돼?"),
            testMessage(id: "m2", senderID: "s2", body: "저는 목요일이요")
        ]
    )

    let resolved = await queue(now: now)

    #expect(resolved.map(\.state) == [.sent])
    #expect(await sender.sent.map(\.text) == ["네 좋아요"])
}

@Test
func switchingARoomBackToDraftOnlyCancelsItsQueuedSend() async {
    let sender = FakeMessageSender()
    var policy = autoSendPolicy()
    policy.deliveryMode = .draftOnly
    let queue = makeQueue(sendStore: FakeSendStore([queued()]), sender: sender, policy: policy)

    #expect(await queue(now: now).map(\.state) == [.cancelled])
    #expect(await sender.sent.isEmpty)
}

@Test
func aFailedSendIsRecordedRatherThanSilentlyDropped() async {
    let log = FakeActionLog()
    let queue = makeQueue(
        sendStore: FakeSendStore([queued()]),
        sender: FakeMessageSender(failure: SendFailure.refused),
        log: log
    )

    let resolved = await queue(now: now)

    #expect(resolved.map(\.state) == [.failed])
    #expect(await log.recorded.first?.kind == .failed)
    #expect(resolved.first?.detail.contains("카카오톡") == true)
}

@Test
func anEmptyQueueDoesNoWork() async {
    let sender = FakeMessageSender()
    let queue = makeQueue(sendStore: FakeSendStore(), sender: sender)

    #expect(await queue(now: now).isEmpty)
    #expect(await sender.sent.isEmpty)
}

// MARK: - Fixtures

private enum SendFailure: LocalizedError {
    case refused
    var errorDescription: String? { "카카오톡 창을 찾지 못했습니다." }
}

private func autoSendPolicy() -> RoomPolicy {
    RoomPolicy(
        accountFingerprint: testAccount.fingerprint,
        chatRoomID: testDirectRoom.id,
        responseMode: .automatic,
        deliveryMode: .autoSendWhenIdle
    )
}

private func queued(
    eligibleAt: Date = now.addingTimeInterval(-1),
    triggerSenderID: String? = "s1"
) -> PendingSend {
    PendingSend(
        id: 1,
        accountFingerprint: testAccount.fingerprint,
        chatRoomID: testDirectRoom.id,
        triggerMessageID: "m1",
        triggerSenderID: triggerSenderID,
        text: "네 좋아요",
        eligibleAt: eligibleAt,
        createdAt: now.addingTimeInterval(-60)
    )
}

private func makeQueue(
    sendStore: FakeSendStore,
    sender: FakeMessageSender,
    log: FakeActionLog = FakeActionLog(),
    settings: FakeSettingsStore = FakeSettingsStore(),
    policy: RoomPolicy = autoSendPolicy(),
    messages: [ChatMessage] = [testMessage(id: "m1", body: "내일 시간 돼?")],
    activity: any SystemActivityMonitor = FixedActivityMonitor(),
    waker: (any DisplayWaker)? = nil,
    rooms: [ChatRoom] = [testDirectRoom],
    roomsFailure: Error? = nil
) -> ProcessSendQueue {
    ProcessSendQueue(
        connection: FakeKakaoConnection(
            rooms: rooms,
            messagesByRoom: [testDirectRoom.id: messages],
            roomsFailure: roomsFailure
        ),
        policyStore: FakePolicyStore([policy]),
        settingsStore: settings,
        sendStore: sendStore,
        actionLog: log,
        sender: sender,
        activityMonitor: activity,
        displayWaker: waker
    )
}

// MARK: - Locked screen

/// Measured on a real Mac: the display sleeping puts the lock screen in front
/// within a second, and katok refuses to type when KakaoTalk is not frontmost.
/// Waking inside the password grace period restores the front and the send goes.
@Test
func aLockedScreenIsWokenSoTheDraftCanBeDelivered() async {
    let monitor = MutableActivityMonitor(screenLocked: true)
    let waker = FakeDisplayWaker(monitor: monitor)
    let sender = FakeMessageSender()
    let queue = makeQueue(
        sendStore: FakeSendStore([queued()]),
        sender: sender,
        activity: monitor,
        waker: waker
    )

    #expect(await queue(now: now).map(\.state) == [.sent])
    #expect(await waker.wakeCount == 1)
    #expect(await sender.sent.count == 1)
}

@Test
func aScreenThatStaysLockedKeepsTheDraftQueuedInsteadOfFailingIt() async {
    let waker = StubbornDisplayWaker()
    let sendStore = FakeSendStore([queued()])
    let sender = FakeMessageSender()
    let queue = makeQueue(
        sendStore: sendStore,
        sender: sender,
        activity: MutableActivityMonitor(screenLocked: true),
        waker: waker
    )

    #expect(await queue(now: now).isEmpty)
    #expect(await waker.wakeCount == 1)
    #expect(await sender.sent.isEmpty)
    #expect(try! await sendStore.waiting().count == 1)
}

@Test
func theScreenIsNotWokenWhenTheUserTurnedThatOff() async {
    let monitor = MutableActivityMonitor(screenLocked: true)
    let waker = FakeDisplayWaker(monitor: monitor)
    let queue = makeQueue(
        sendStore: FakeSendStore([queued()]),
        sender: FakeMessageSender(),
        settings: FakeSettingsStore(wakesDisplay: false),
        activity: monitor,
        waker: waker
    )

    #expect(await queue(now: now).isEmpty)
    #expect(await waker.wakeCount == 0)
}

/// Waking lights up the screen, so it must not happen for a draft that is still
/// settling and would be held anyway.
@Test
func theScreenIsNotWokenForDraftsThatAreNotDueYet() async {
    let monitor = MutableActivityMonitor(screenLocked: true)
    let waker = FakeDisplayWaker(monitor: monitor)
    let queue = makeQueue(
        sendStore: FakeSendStore([queued(eligibleAt: Date().addingTimeInterval(300))]),
        sender: FakeMessageSender(),
        activity: monitor,
        waker: waker
    )

    #expect(await queue(now: now).isEmpty)
    #expect(await waker.wakeCount == 0)
}

/// katok reports "nothing was sent; retry" when it could not reach the front.
/// Recording that as a failure would drop a message the user asked to send.
@Test
func aRetryableSendFailureLeavesTheDraftQueued() async {
    let sendStore = FakeSendStore([queued()])
    let log = FakeActionLog()
    let queue = makeQueue(
        sendStore: sendStore,
        sender: FakeMessageSender(
            failure: MessageSendFailure(message: "not frontmost; retry", isRetryable: true)
        ),
        log: log
    )

    #expect(await queue(now: now).isEmpty)
    #expect(try! await sendStore.waiting().count == 1)
    #expect(await log.recorded.isEmpty)
}

// MARK: - A room whose window is closed

/// Watched happen: a reply sat unsent for ten minutes while the queue retried
/// every few seconds, and the only record of why lived in a database column.
/// Retrying is right — the send works the moment the window opens — but silence
/// is not, so the reason goes where drafts are reviewed and says what to do.
@Test
func aClosedRoomExplainsItselfOnTheScreenInsteadOfRetryingInSilence() async throws {
    let sendStore = FakeSendStore([queued()])
    let log = FakeActionLog()
    let queue = makeQueue(
        sendStore: sendStore,
        sender: FakeMessageSender(failure: roomWindowClosed),
        log: log
    )

    #expect(await queue(now: now).isEmpty)

    #expect(try await sendStore.waiting().count == 1)
    #expect(await log.recorded.count == 1)
    #expect(await log.recorded.first?.kind == .failed)
    #expect(await log.recorded.first?.detail.contains("대화창을 열어두어야") == true)
    #expect(try await sendStore.waiting().first?.detail.contains("대화창을 열어두어야") == true)
}

/// The queue comes back every few seconds. One row per attempt would bury the
/// timeline the row exists to explain.
@Test
func aClosedRoomIsReportedOncePerReasonRatherThanOncePerAttempt() async {
    let log = FakeActionLog()
    let queue = makeQueue(
        sendStore: FakeSendStore([queued()]),
        sender: FakeMessageSender(failure: roomWindowClosed),
        log: log
    )

    await queue(now: now)
    await queue(now: now)
    await queue(now: now)

    #expect(await log.recorded.count == 1)
}

/// A passing screen state still says "재시도 중". It resolves on its own, and
/// telling somebody to act on it would send them looking for nothing.
@Test
func anOrdinaryRetryStillLeavesNoTimelineRow() async {
    let log = FakeActionLog()
    let queue = makeQueue(
        sendStore: FakeSendStore([queued()]),
        sender: FakeMessageSender(
            failure: MessageSendFailure(message: "not frontmost; retry", isRetryable: true)
        ),
        log: log
    )

    await queue(now: now)

    #expect(await log.recorded.isEmpty)
}

private let roomWindowClosed = MessageSendFailure(
    message: "전송에 실패했습니다. Error: 'hangyeol' is not in the chat list",
    isRetryable: true,
    cause: .roomWindowClosed
)

@Test
func aTerminalSendFailureStillEndsTheDraft() async {
    let sendStore = FakeSendStore([queued()])
    let queue = makeQueue(
        sendStore: sendStore,
        sender: FakeMessageSender(
            failure: MessageSendFailure(message: "katok 실행 파일을 찾을 수 없습니다.", isRetryable: false)
        )
    )

    #expect(await queue(now: now).map(\.state) == [.failed])
    #expect(try! await sendStore.waiting().isEmpty)
}

// MARK: - Unreadable room list

private enum ArchiveBusy: Error { case locked }

/// katok rewrites the archive every few seconds, so a read can land mid-write
/// and fail. Treating that as "the room is gone" cancelled replies the user was
/// waiting on, and a cancelled draft never comes back.
@Test
func aDraftSurvivesARoomListThatCouldNotBeRead() async throws {
    let sendStore = FakeSendStore([queued()])
    let sender = FakeMessageSender()
    let log = FakeActionLog()
    let queue = makeQueue(
        sendStore: sendStore,
        sender: sender,
        log: log,
        roomsFailure: ArchiveBusy.locked
    )

    #expect(await queue(now: now).isEmpty)
    #expect(await sender.sent.isEmpty)
    #expect(try await sendStore.waiting().count == 1)
    #expect(await log.recorded.isEmpty)
}

/// The same holds for a read that succeeds and answers nothing. An archive that
/// briefly lists no rooms at all is a failed read wearing a different hat.
@Test
func aDraftSurvivesAnEmptyRoomList() async throws {
    let sendStore = FakeSendStore([queued()])
    let sender = FakeMessageSender()
    let queue = makeQueue(sendStore: sendStore, sender: sender, rooms: [])

    #expect(await queue(now: now).isEmpty)
    #expect(try await sendStore.waiting().count == 1)
}
