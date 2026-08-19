import Foundation
import Testing
import TalkFlowDomain
@testable import TalkFlowApplication

// MARK: - 뒷말 대기

/// A message arriving inside the wait must change the answer, not destroy it.
/// The follow-up is folded into a second request rather than cancelling a draft
/// somebody already paid for — which is what the send gate used to do to it.
@Test
func aMessageArrivingDuringTheWaitIsAnsweredInsteadOfCancellingTheDraft() async {
    let generator = FakeReplyGenerator(drafts: [stillTyping, finished])
    let connection = MutableKakaoConnection(
        messages: [testMessage(id: "m1", body: "내일 회의 자료 말인데")]
    )
    let pipeline = pacingPipeline(
        connection: connection,
        generator: generator,
        pause: { _ in
            await connection.receive(testMessage(id: "m2", body: "그거 오늘까지 필요할까요?"))
        }
    )

    let actions = await pipeline(changedChatRoomIDs: [testDirectRoom.id])

    #expect(await generator.callCount == 2)
    #expect(await generator.lastRequest?.recentMessages.map(\.id) == ["m1", "m2"])
    #expect(actions.first?.kind == .drafted)
    #expect(actions.first?.triggerMessageID == "m2")
}

/// And when nothing follows, the wait ends and the reply goes out about the
/// message that was there all along — without a second call, because asking
/// again about an unchanged room would buy the same answer twice.
@Test
func theReplyStillGoesOutWhenTheWaitPassesWithNothingNew() async {
    let generator = FakeReplyGenerator(drafts: [stillTyping])
    let waits = WaitRecorder()
    let pipeline = pacingPipeline(
        connection: MutableKakaoConnection(
            messages: [testMessage(id: "m1", body: "내일 회의 자료 말인데")]
        ),
        generator: generator,
        pause: { await waits.record($0) }
    )

    let actions = await pipeline(changedChatRoomIDs: [testDirectRoom.id])

    #expect(await waits.recorded == [FollowUpWait.defaultDelay])
    #expect(await generator.callCount == 1)
    #expect(actions.first?.kind == .drafted)
    #expect(actions.first?.triggerMessageID == "m1")
}

/// The common case, and the one the whole change is for: the model says the
/// person is finished, and the reply goes out with no wait at all. The pause is
/// for somebody mid-thought, not a tax on every reply.
@Test
func aFinishedMessageIsAnsweredWithoutWaiting() async {
    let waits = WaitRecorder()
    let pipeline = pacingPipeline(
        connection: MutableKakaoConnection(
            messages: [testMessage(id: "m1", body: "내일 두 시에 봅시다.")]
        ),
        pause: { await waits.record($0) }
    )

    let actions = await pipeline(changedChatRoomIDs: [testDirectRoom.id])

    #expect(await waits.recorded.isEmpty)
    #expect(actions.first?.kind == .drafted)
}

/// A model that keeps asking for more time cannot hold a reply forever. Somebody
/// writing a long thought in pieces gets the extra rounds; a provider that always
/// sets the flag costs a bounded delay and then the answer goes out.
@Test
func aModelThatKeepsAskingToWaitIsCutOffAfterItsRounds() async {
    let generator = FakeReplyGenerator(drafts: [stillTyping])
    let waits = WaitRecorder()
    let connection = MutableKakaoConnection(
        messages: [testMessage(id: "m1", body: "내일 회의 자료 말인데")]
    )
    let pipeline = pacingPipeline(
        connection: connection,
        generator: generator,
        pause: { seconds in
            await waits.record(seconds)
            await connection.receive(
                testMessage(id: "m\(await waits.recorded.count + 1)", body: "그리고 하나 더 있는데")
            )
        }
    )

    let actions = await pipeline(changedChatRoomIDs: [testDirectRoom.id])

    #expect(await generator.callCount == FollowUpWait.maximumRounds)
    #expect(await waits.recorded.count == FollowUpWait.maximumRounds - 1)
    #expect(actions.first?.kind == .drafted)
}

/// The wait is not a licence to skip the checks that decided the reply was
/// wanted. Ten seconds is long enough for the user to have answered by hand, and
/// sending then would be the second reply to one message.
@Test
func aReplyIsDroppedWhenThePersonWasAnsweredDuringTheWait() async {
    let generator = FakeReplyGenerator(drafts: [stillTyping])
    let connection = MutableKakaoConnection(
        messages: [testMessage(id: "m1", body: "내일 회의 자료 말인데")]
    )
    let pipeline = pacingPipeline(
        connection: connection,
        generator: generator,
        pause: { _ in
            await connection.receive(
                testMessage(id: "m2", body: "아 그거 내가 봤어", isFromMe: true)
            )
        }
    )

    let actions = await pipeline(changedChatRoomIDs: [testDirectRoom.id])

    #expect(await generator.callCount == 1)
    #expect(actions.filter { $0.kind == .drafted }.isEmpty)
}

// MARK: - Judging in batches

/// The cost this setting exists for. Three messages arrive in three syncs and the
/// model is asked once, where a room judging each message would have been asked
/// three times.
@Test
func aBatchingRoomAsksOnceWhereAnImmediateRoomAsksEveryTime() async {
    let batched = FakeReplyGenerator()
    let batching = await run(threeSyncsAgainst: pacingPolicy(judgementInterval: JudgementInterval(fixed: 600)), generator: batched)
    let immediate = FakeReplyGenerator()
    let perMessage = await run(threeSyncsAgainst: pacingPolicy(), generator: immediate)

    #expect(await batched.callCount == 1)
    #expect(batching.filter { $0.kind == .drafted }.count == 1)
    #expect(await immediate.callCount == 3)
    #expect(perMessage.filter { $0.kind == .drafted }.count == 3)
}

/// And the one call it does make carries everything that piled up, so nothing
/// said during the interval goes unread.
@Test
func theOneBatchedCallCarriesEverythingThatAccumulated() async {
    let generator = FakeReplyGenerator()
    let pipeline = pacingPipeline(
        connection: MutableKakaoConnection(
            messages: (1...3).map { testMessage(id: "m\($0)", body: "메시지 \($0)번입니다") }
        ),
        policy: pacingPolicy(judgementInterval: JudgementInterval(fixed: 600)),
        log: FakeActionLog(lastJudgement: Date().addingTimeInterval(-700)),
        generator: generator
    )

    await pipeline(changedChatRoomIDs: [testDirectRoom.id])

    #expect(await generator.callCount == 1)
    #expect(await generator.lastRequest?.recentMessages.map(\.id) == ["m1", "m2", "m3"])
}

/// Accumulating is not an excuse to hand one call an unbounded prompt. The
/// oldest come off and the model is told how many it is missing, which is as far
/// as this goes — condensing what was dropped is a separate feature.
@Test
func aBatchTooLongForOneCallDropsItsOldestAndSaysSo() async {
    let generator = FakeReplyGenerator()
    let pipeline = pacingPipeline(
        connection: MutableKakaoConnection(
            messages: (1...20).map {
                testMessage(id: "m\($0)", body: String(repeating: "가", count: 400))
            }
        ),
        policy: pacingPolicy(judgementInterval: JudgementInterval(fixed: 600)),
        log: FakeActionLog(lastJudgement: Date().addingTimeInterval(-700)),
        generator: generator
    )

    await pipeline(changedChatRoomIDs: [testDirectRoom.id])

    let request = await generator.lastRequest
    let carried = request?.recentMessages.map(\.body.count).reduce(0, +) ?? 0
    #expect(carried <= ConversationWindow.characterBudget)
    #expect(request?.recentMessages.last?.id == "m20")
    #expect(request?.omittedMessageCount == 20 - (request?.recentMessages.count ?? 0))
    #expect((request?.omittedMessageCount ?? 0) > 0)
}

/// The same saving in the rooms a clock cannot buy it in. Where messages arrive
/// ten minutes apart, a cycle of minutes expires between every pair of them and
/// the room ends up answering each one; a cycle of three messages asks once for
/// three, however long the three take to arrive.
@Test
func aRoomCountingMessagesAsksOnceWhenItsCountFillsUp() async {
    let judged = Date(timeIntervalSince1970: 1_000_000)
    let generator = FakeReplyGenerator()
    let connection = MutableKakaoConnection()
    let pipeline = pacingPipeline(
        connection: connection,
        policy: pacingPolicy(judgementInterval: JudgementInterval(fixed: 3, measure: .messages)),
        log: FakeActionLog(lastJudgement: judged),
        generator: generator
    )
    let messages = (1...3).map {
        testMessage(
            id: "m\($0)",
            body: "메시지 \($0)번입니다",
            sentAt: judged.addingTimeInterval(Double($0) * 600)
        )
    }

    var recorded: [AgentAction] = []
    for count in 1...3 {
        await connection.hold(Array(messages.prefix(count)))
        recorded += await pipeline(changedChatRoomIDs: [testDirectRoom.id])
    }

    #expect(await generator.callCount == 1)
    #expect(await generator.lastRequest?.recentMessages.map(\.id) == ["m1", "m2", "m3"])
    #expect(recorded.filter { $0.kind == .drafted }.count == 1)
}

/// Accumulating is expected silence at the volume of every message in the
/// interval. Recording it would bury the drafts and failures the timeline is for.
@Test
func aRoomAccumulatingItsBatchLeavesNoTimelineRows() async {
    let log = FakeActionLog(lastJudgement: Date())
    let pipeline = pacingPipeline(
        connection: MutableKakaoConnection(
            messages: [testMessage(id: "m1", body: "이거 어떻게 할까요?")]
        ),
        policy: pacingPolicy(judgementInterval: JudgementInterval(fixed: 600)),
        log: log
    )

    #expect(await pipeline(changedChatRoomIDs: [testDirectRoom.id]).isEmpty)
    #expect(await log.recorded.isEmpty)
}

// MARK: - 답한 대화 기록

/// The wait folds a follow-up into the same answer, so the record has to name
/// both messages. Naming only the last one leaves a reply that answers two
/// sitting under a line it does not follow from.
@Test
func theRecordOfAFollowUpRunCarriesTheMessageTheWaitFoldedIn() async {
    let connection = MutableKakaoConnection(
        messages: [testMessage(id: "m1", body: "내일 회의 자료 말인데")]
    )
    let pipeline = pacingPipeline(
        connection: connection,
        generator: FakeReplyGenerator(drafts: [stillTyping, finished]),
        pause: { _ in
            await connection.receive(testMessage(id: "m2", body: "그거 오늘까지 필요할까요?"))
        }
    )

    let run = await pipeline(changedChatRoomIDs: [testDirectRoom.id]).first?.answeredRun

    #expect(run?.lines.map(\.messageID) == ["m1", "m2"])
    #expect(run?.omittedCount == 0)
}

/// A room on 즉시 answers the message that arrived, so its record stays the one
/// line it always was. The run is not an excuse to quote the whole window back.
@Test
func aRoomJudgingEachMessageRecordsThatOneMessage() async {
    let pipeline = pacingPipeline(
        connection: MutableKakaoConnection(
            messages: [
                testMessage(id: "m1", senderID: "s2", body: "어제 그 얘기 말이에요."),
                testMessage(id: "m2", body: "내일 두 시에 봅시다.")
            ]
        )
    )

    let run = await pipeline(changedChatRoomIDs: [testDirectRoom.id]).first?.answeredRun

    #expect(run?.lines.map(\.messageID) == ["m2"])
}

/// The interval's own gap: one call answers everything that piled up, and the
/// record has to hold the same batch the model was asked about.
@Test
func theRecordOfABatchCarriesEverythingThatAccumulated() async {
    let judged = Date(timeIntervalSince1970: 1_000_000)
    let pipeline = pacingPipeline(
        connection: MutableKakaoConnection(
            messages: (1...3).map {
                testMessage(
                    id: "m\($0)",
                    body: "메시지 \($0)번입니다",
                    sentAt: judged.addingTimeInterval(Double($0) * 60)
                )
            }
        ),
        policy: pacingPolicy(judgementInterval: JudgementInterval(fixed: 600)),
        log: FakeActionLog(lastJudgement: judged)
    )

    let run = await pipeline(changedChatRoomIDs: [testDirectRoom.id]).first?.answeredRun

    #expect(run?.lines.map(\.messageID) == ["m1", "m2", "m3"])
}

/// Whatever the model was asked about, the record is bounded: an interval in an
/// active room accumulates more than a person will read. The newest survive and
/// the number that came off is carried, so the pane never shows part of a run as
/// the whole of one.
@Test
func aRecordedRunIsCappedAndSaysHowMuchItLeftOut() async {
    let judged = Date(timeIntervalSince1970: 1_000_000)
    let pipeline = pacingPipeline(
        connection: MutableKakaoConnection(
            messages: (1...26).map {
                testMessage(
                    id: "m\($0)",
                    body: "메시지 \($0)번입니다",
                    sentAt: judged.addingTimeInterval(Double($0))
                )
            }
        ),
        policy: pacingPolicy(judgementInterval: JudgementInterval(fixed: 600)),
        log: FakeActionLog(lastJudgement: judged)
    )

    let run = await pipeline(changedChatRoomIDs: [testDirectRoom.id]).first?.answeredRun

    #expect(run?.lines.count == AnsweredRun.messageLimit)
    #expect(run?.lines.last?.messageID == "m26")
    #expect(run?.omittedCount == 6)
}

// MARK: - Fixtures

/// The model's two answers to 「이 사람 아직 할 말 남았나」, which is the only thing
/// that makes a reply wait now.
private let stillTyping = ReplyDraft(
    shouldReply: true,
    mode: .directQuestion,
    confidence: .high,
    text: "네 좋아요",
    expectsMore: true
)

private let finished = ReplyDraft(
    shouldReply: true,
    mode: .directQuestion,
    confidence: .high,
    text: "네 좋아요"
)

private func pacingPolicy(judgementInterval: JudgementInterval = .immediate) -> RoomPolicy {
    RoomPolicy(
        accountFingerprint: testAccount.fingerprint,
        chatRoomID: testDirectRoom.id,
        responseMode: .automatic,
        minimumInterval: 0,
        judgementInterval: judgementInterval
    )
}

/// Remembers what it was asked to wait for instead of waiting.
private actor WaitRecorder {
    private(set) var recorded: [TimeInterval] = []

    func record(_ seconds: TimeInterval) { recorded.append(seconds) }
}

/// Three syncs on one room, each carrying a message the last did not, which is
/// how a conversation reaches the pipeline in life.
private func run(
    threeSyncsAgainst policy: RoomPolicy,
    generator: FakeReplyGenerator
) async -> [AgentAction] {
    let messages = (1...3).map { testMessage(id: "m\($0)", body: "메시지 \($0)번입니다") }
    let connection = MutableKakaoConnection()
    let pipeline = pacingPipeline(connection: connection, policy: policy, generator: generator)

    var recorded: [AgentAction] = []
    for count in 1...3 {
        await connection.hold(Array(messages.prefix(count)))
        recorded += await pipeline(changedChatRoomIDs: [testDirectRoom.id])
    }
    return recorded
}

/// The wait is real seconds in production and none at all by default here, so a
/// test only pays for it when the test is about it.
private func pacingPipeline(
    connection: MutableKakaoConnection,
    policy: RoomPolicy = pacingPolicy(),
    log: FakeActionLog = FakeActionLog(),
    generator: FakeReplyGenerator = FakeReplyGenerator(),
    pause: @escaping @Sendable (TimeInterval) async -> Void = { _ in }
) -> DraftRepliesForChangedRooms {
    DraftRepliesForChangedRooms(
        connection: connection,
        policyStore: FakePolicyStore([policy]),
        settingsStore: FakeSettingsStore(),
        actionLog: log,
        generator: generator,
        pause: pause
    )
}
