import Foundation
import Testing
import TalkFlowDomain
@testable import TalkFlowApplication

private let detected = Date(timeIntervalSince1970: 1_000_000)
private let synchronized = detected.addingTimeInterval(7)

// MARK: - Fixtures

private func timedPipeline(
    log: FakeActionLog,
    generator: FakeReplyGenerator = FakeReplyGenerator()
) -> DraftRepliesForChangedRooms {
    DraftRepliesForChangedRooms(
        connection: FakeKakaoConnection(
            status: .connected(account: testAccount),
            rooms: [testDirectRoom],
            messagesByRoom: [testDirectRoom.id: [testMessage(id: "m1", body: "내일 시간 돼?")]]
        ),
        policyStore: FakePolicyStore([
            RoomPolicy(
                accountFingerprint: testAccount.fingerprint,
                chatRoomID: testDirectRoom.id,
                responseMode: .automatic,
                minimumInterval: 0
            )
        ]),
        settingsStore: FakeSettingsStore(),
        actionLog: log,
        generator: generator,
        pause: { _ in }
    )
}

private func timedQueue(
    sendStore: FakeSendStore,
    log: FakeActionLog = FakeActionLog(),
    settings: FakeSettingsStore = FakeSettingsStore()
) -> ProcessSendQueue {
    ProcessSendQueue(
        connection: FakeKakaoConnection(
            rooms: [testDirectRoom],
            messagesByRoom: [testDirectRoom.id: [testMessage(id: "m1", body: "내일 시간 돼?")]]
        ),
        policyStore: FakePolicyStore([
            RoomPolicy(
                accountFingerprint: testAccount.fingerprint,
                chatRoomID: testDirectRoom.id,
                responseMode: .automatic,
                deliveryMode: .autoSendWhenIdle
            )
        ]),
        settingsStore: settings,
        sendStore: sendStore,
        actionLog: log,
        sender: FakeMessageSender(),
        activityMonitor: FixedActivityMonitor()
    )
}

private func waitingSend(
    eligibleAt: Date,
    detail: String = "",
    createdAt: Date = detected
) -> PendingSend {
    PendingSend(
        id: 1,
        accountFingerprint: testAccount.fingerprint,
        chatRoomID: testDirectRoom.id,
        triggerMessageID: "m1",
        text: "네 좋아요",
        eligibleAt: eligibleAt,
        detail: detail,
        createdAt: createdAt
    )
}

// MARK: - The drafting half

/// The delay a person actually experiences starts when KakaoTalk's database
/// moved, not when this pipeline was handed the room. Those are seconds apart —
/// the detection loop waits out its interval and then runs a sync — and a record
/// that started its clock at the second one would leave the largest fixed cost
/// on the path outside the record entirely.
@Test
func aDraftRecordsTheSyncItWasCausedBy() async throws {
    let log = FakeActionLog()
    let pipeline = timedPipeline(log: log)

    _ = await pipeline(
        changedChatRoomIDs: [testDirectRoom.id],
        detectedAt: detected,
        synchronizedAt: synchronized
    )

    let timeline = try #require(await log.recorded.first?.timeline)
    #expect(timeline.steps.first?.stage == .detected)
    #expect(timeline.steps.first?.at == detected)
    #expect(timeline.steps.dropFirst().first?.stage == .synchronized)
    #expect(timeline.steps.dropFirst().first?.at == synchronized)
}

/// The model call is the span this whole record was added to measure, so it has
/// to be its own pair of stamps rather than being folded into whatever ran
/// around it.
@Test
func aDraftRecordsTheModelCallAsItsOwnStage() async throws {
    let log = FakeActionLog()
    let pipeline = timedPipeline(log: log)

    _ = await pipeline(changedChatRoomIDs: [testDirectRoom.id], synchronizedAt: synchronized)

    let stages = try #require(await log.recorded.first?.timeline).steps.map(\.stage)
    #expect(stages.contains(.judged))
    #expect(stages.contains(.contextPrepared))
    #expect(stages.contains(.modelRequested))
    #expect(stages.contains(.modelAnswered))
}

/// A call that failed is the case somebody is most likely to come looking at, so
/// the stages leading up to it stay and the failure names itself at the end.
@Test
func aFailedCallKeepsTheStagesItGotThroughAndNamesTheFailure() async throws {
    let log = FakeActionLog()
    let pipeline = timedPipeline(log: log, generator: FakeReplyGenerator(draft: nil))

    _ = await pipeline(changedChatRoomIDs: [testDirectRoom.id], synchronizedAt: synchronized)

    let timeline = try #require(await log.recorded.first?.timeline)
    #expect(timeline.steps.map(\.stage).contains(.modelRequested))
    #expect(timeline.steps.last?.stage == .failed)
    #expect(timeline.steps.last?.note == "Codex를 호출하지 못했습니다.")
}

/// The queue's half of the story: how long the draft sat, and how long typing it
/// into KakaoTalk took. Its 전송 대기열 등록 is stamped from the entry's own
/// creation time, which is what makes the wait measurable at all.
@Test
func aDeliveryRecordsTheWaitAndTheTypingSeparately() async throws {
    let sendStore = FakeSendStore([waitingSend(eligibleAt: detected)])
    let log = FakeActionLog()
    let queue = timedQueue(sendStore: sendStore, log: log)

    _ = await queue(now: detected.addingTimeInterval(60))

    let timeline = try #require(await log.recorded.first?.timeline)
    #expect(timeline.steps.map(\.stage) == [.queued, .sendAttempted, .sent])
    #expect(timeline.steps.first?.at == detected)
}

/// A draft that is patiently waiting and one that is stuck look identical from
/// outside the queue, which is exactly the question when nothing is arriving.
/// The reason is written onto the entry so the delivery can carry it later.
@Test
func aWaitingDraftHasItsReasonWrittenDown() async throws {
    let sendStore = FakeSendStore([waitingSend(eligibleAt: detected.addingTimeInterval(30))])
    let queue = timedQueue(sendStore: sendStore)

    _ = await queue(now: detected)

    #expect(try await sendStore.waiting().first?.detail == "안정화 시간이 30초 남았습니다.")
}

/// Rewritten only when it changes. The queue comes back every ten seconds, and a
/// write per tick for a fact that has not moved is noise in the one column that
/// is supposed to explain the wait.
@Test
func aWaitingDraftIsNotRewrittenWhileTheReasonHoldsStill() async throws {
    let sendStore = FakeSendStore([
        waitingSend(
            eligibleAt: detected.addingTimeInterval(30),
            detail: "안정화 시간이 30초 남았습니다."
        )
    ])
    let queue = timedQueue(sendStore: sendStore)

    _ = await queue(now: detected)

    #expect(await sendStore.resolutions.isEmpty)
}

/// A quarter of this queue's drafts are dropped as 대화가 이어져, and how long
/// they lived before that is the measurement of whether generation is keeping up
/// with the room.
@Test
func aCancelledDraftStillRecordsHowLongItLived() async throws {
    let sendStore = FakeSendStore([waitingSend(eligibleAt: detected)])
    let log = FakeActionLog()
    let queue = timedQueue(
        sendStore: sendStore,
        log: log,
        settings: FakeSettingsStore(enabled: false)
    )

    _ = await queue(now: detected.addingTimeInterval(45))

    let timeline = try #require(await log.recorded.first?.timeline)
    #expect(timeline.steps.map(\.stage) == [.queued, .cancelled])
    // Not exactly 45: the stamps carry the pass's real elapsed time on top of
    // the instant the test named, which is what stops two entries delivered
    // seconds apart from claiming the same one.
    #expect(abs((timeline.duration ?? 0) - 45) < 1)
}
