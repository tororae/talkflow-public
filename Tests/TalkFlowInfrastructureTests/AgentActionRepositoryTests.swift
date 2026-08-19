import Foundation
import GRDB
import Testing
import TalkFlowDomain
@testable import TalkFlowInfrastructure

private let account = "katok-test"

private func makeRepository() throws -> (AgentActionRepository, TalkFlowDatabase, () -> Void) {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "talkflow-actions-\(UUID().uuidString)/talkflow.sqlite")
    let database = try TalkFlowDatabase(fileURL: url)
    return (
        AgentActionRepository(database: database),
        database,
        { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    )
}

private func action(
    kind: AgentAction.Kind,
    roomID: String = "room-1",
    triggerMessageID: String? = "m1",
    replyText: String? = nil,
    run: AnsweredRun? = nil,
    at date: Date = Date(timeIntervalSince1970: 1_000_000)
) -> AgentAction {
    AgentAction(
        accountFingerprint: account,
        chatRoomID: roomID,
        kind: kind,
        triggerMessageID: triggerMessageID,
        triggerSenderID: "s1",
        answeredRun: run,
        replyMode: .mention,
        confidence: .high,
        replyText: replyText,
        detail: "테스트",
        contextMessageCount: 12,
        createdAt: date
    )
}

@Test
func aRecordedActionReadsBackWithEveryFieldIntact() async throws {
    let (repository, _, cleanup) = try makeRepository()
    defer { cleanup() }

    try await repository.record(action(kind: .drafted, replyText: "네 좋아요"))
    let stored = try await repository.recent(limit: 10)

    #expect(stored.count == 1)
    #expect(stored.first?.kind == .drafted)
    #expect(stored.first?.replyText == "네 좋아요")
    #expect(stored.first?.replyMode == .mention)
    #expect(stored.first?.confidence == .high)
    #expect(stored.first?.contextMessageCount == 12)
}

/// The run is written once with the action and never rebuilt: the archive it was
/// read out of gets pruned, and the timeline is append-only. So it has to make
/// the trip to disk whole.
@Test
func theRunAnActionAnsweredSurvivesTheRoundTrip() async throws {
    let (repository, _, cleanup) = try makeRepository()
    defer { cleanup() }
    let run = AnsweredRun(
        lines: [
            AnsweredRun.Line(
                messageID: "m1",
                senderName: "지수",
                sentAt: Date(timeIntervalSince1970: 1_000_000),
                body: "내일 회의 자료 말인데"
            ),
            AnsweredRun.Line(
                messageID: "m2",
                senderName: "지수",
                sentAt: Date(timeIntervalSince1970: 1_000_030),
                body: "그거 오늘까지 필요할까요?"
            )
        ],
        omittedCount: 3
    )

    try await repository.record(action(kind: .drafted, replyText: "네 좋아요", run: run))

    #expect(try await repository.recent(limit: 1).first?.answeredRun == run)
}

/// A hold answered nothing, so its column stays empty rather than claiming a run
/// of one. Empty means the same thing there as it does on the older rows.
@Test
func anActionThatAnsweredNothingStoresNoRun() async throws {
    let (repository, _, cleanup) = try makeRepository()
    defer { cleanup() }

    try await repository.record(action(kind: .held))

    #expect(try await repository.recent(limit: 1).first?.answeredRun == nil)
}

/// The rows recorded before runs existed kept a trigger line and nothing else,
/// and that line is all the history there is for them. They have to keep reading
/// the way they always did rather than come back blank.
@Test
func anActionRecordedBeforeRunsExistedStillReadsBackItsTrigger() async throws {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "talkflow-action-migration-\(UUID().uuidString)/talkflow.sqlite")
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    try seedActionAtTriggerOnlySchema(at: url)

    let stored = try await AgentActionRepository(database: try TalkFlowDatabase(fileURL: url))
        .recent(limit: 10)

    #expect(stored.count == 1)
    #expect(stored.first?.answeredRun == nil)
    #expect(stored.first?.triggerText == "언제 와?")
    #expect(stored.first?.triggerSenderName == "지수")
    #expect(stored.first?.replyText == "곧 도착해요")
    #expect(stored.first?.contextMessageCount == 12)
}

/// The schema the shipped build writes today: one trigger message per action and
/// no room for the rest of what it answered.
private func seedActionAtTriggerOnlySchema(at url: URL) throws {
    let queue = try DatabaseQueue(path: url.path)
    try TalkFlowDatabase.migrator.migrate(queue, upTo: "v9-room-judgement-interval-range")
    try queue.write { db in
        try db.execute(
            sql: """
            INSERT INTO agent_actions
                (account_fingerprint, chat_id, kind, trigger_message_id, trigger_sender_id,
                 trigger_text, trigger_sender_name, reply_mode, confidence, reply_text,
                 detail, context_message_count, created_at)
            VALUES (?, 'room-1', 'drafted', 'm1', 's1', ?, ?, 'mention', 'high', ?, ?, 12, ?)
            """,
            arguments: [
                account,
                "언제 와?",
                "지수",
                "곧 도착해요",
                "초안을 만들었습니다.",
                Date(timeIntervalSince1970: 1_000_000)
            ]
        )
    }
    try queue.close()
}

@Test
func theTimelineReadsNewestFirst() async throws {
    let (repository, _, cleanup) = try makeRepository()
    defer { cleanup() }

    try await repository.record(action(kind: .held, triggerMessageID: "m1", at: Date(timeIntervalSince1970: 100)))
    try await repository.record(action(kind: .drafted, triggerMessageID: "m2", at: Date(timeIntervalSince1970: 200)))

    #expect(try await repository.recent(limit: 10).map(\.triggerMessageID) == ["m2", "m1"])
}

@Test
func aRoomsHistoryExcludesOtherRooms() async throws {
    let (repository, _, cleanup) = try makeRepository()
    defer { cleanup() }

    try await repository.record(action(kind: .drafted, roomID: "room-1", triggerMessageID: "m1"))
    try await repository.record(action(kind: .drafted, roomID: "room-2", triggerMessageID: "m2"))

    #expect(try await repository.recent(chatRoomID: "room-1", limit: 10).map(\.triggerMessageID) == ["m1"])
}

/// The cooldown counts from when TalkFlow last spoke, so a hold must not reset it.
@Test
func onlyDraftsAndSendsCountAsTheLastReply() async throws {
    let (repository, _, cleanup) = try makeRepository()
    defer { cleanup() }

    try await repository.record(action(kind: .drafted, triggerMessageID: "m1", at: Date(timeIntervalSince1970: 100)))
    try await repository.record(action(kind: .held, triggerMessageID: "m2", at: Date(timeIntervalSince1970: 500)))
    try await repository.record(action(kind: .failed, triggerMessageID: "m3", at: Date(timeIntervalSince1970: 900)))

    let last = try await repository.lastReplyDate(chatRoomID: "room-1", accountFingerprint: account)

    #expect(last == Date(timeIntervalSince1970: 100))
}

@Test
func aRoomWithNoRepliesYetHasNoCooldownAnchor() async throws {
    let (repository, _, cleanup) = try makeRepository()
    defer { cleanup() }

    #expect(try await repository.lastReplyDate(chatRoomID: "room-1", accountFingerprint: account) == nil)
}

/// A batch is paced by what it costs, so its anchor is the last row that came
/// from a model call. The context count is what marks one — a cooldown, a send
/// failure, or a dismissal never reached the provider and leaves it at zero.
/// Pacing off those would let a batching room burn a call per sync.
@Test
func onlyRowsThatCostAModelCallAnchorTheNextBatch() async throws {
    let (repository, _, cleanup) = try makeRepository()
    defer { cleanup() }

    try await repository.record(action(kind: .drafted, triggerMessageID: "m1", at: Date(timeIntervalSince1970: 100)))
    try await repository.record(
        AgentAction(
            accountFingerprint: account,
            chatRoomID: "room-1",
            kind: .held,
            triggerMessageID: "m2",
            detail: "최소 응답 간격이 남았습니다.",
            createdAt: Date(timeIntervalSince1970: 900)
        )
    )

    let anchor = try await repository.lastJudgementDate(chatRoomID: "room-1", accountFingerprint: account)

    #expect(anchor == Date(timeIntervalSince1970: 100))
}

/// A model call that came back with nothing still cost the call, so it still
/// starts the next interval. Most calls in the rooms this setting exists for
/// come back with nothing.
@Test
func aCallTheModelDeclinedStillStartsTheNextInterval() async throws {
    let (repository, _, cleanup) = try makeRepository()
    defer { cleanup() }

    try await repository.record(action(kind: .drafted, triggerMessageID: "m1", at: Date(timeIntervalSince1970: 100)))
    try await repository.record(action(kind: .held, triggerMessageID: "m2", at: Date(timeIntervalSince1970: 500)))

    let anchor = try await repository.lastJudgementDate(chatRoomID: "room-1", accountFingerprint: account)

    #expect(anchor == Date(timeIntervalSince1970: 500))
}

@Test
func aRoomNeverJudgedYetHasNoBatchAnchor() async throws {
    let (repository, _, cleanup) = try makeRepository()
    defer { cleanup() }

    #expect(try await repository.lastJudgementDate(chatRoomID: "room-1", accountFingerprint: account) == nil)
}

@Test
func alreadyJudgedMessagesAreRecognised() async throws {
    let (repository, _, cleanup) = try makeRepository()
    defer { cleanup() }

    try await repository.record(action(kind: .drafted, triggerMessageID: "m1"))

    #expect(try await repository.hasAction(chatRoomID: "room-1", triggerMessageID: "m1"))
    #expect(try await repository.hasAction(chatRoomID: "room-1", triggerMessageID: "m2") == false)
    #expect(try await repository.hasAction(chatRoomID: "room-2", triggerMessageID: "m1") == false)
}

@Test
func theTimelineNamesRoomsFromTheRememberedList() async throws {
    let (repository, database, cleanup) = try makeRepository()
    defer { cleanup() }

    try await RoomPolicyRepository(database: database).rememberRooms(
        [ChatRoom(id: "room-1", displayName: "프로젝트 팀", kind: .group)],
        accountFingerprint: account
    )
    try await repository.record(action(kind: .drafted))

    #expect(try await repository.recent(limit: 1).first?.chatRoomName == "프로젝트 팀")
}

// MARK: - Pending drafts

@Test
func onlyDraftsWithTextAndNoOutcomeCountAsPending() async throws {
    let (repository, _, cleanup) = try makeRepository()
    defer { cleanup() }

    try await repository.record(action(kind: .drafted, triggerMessageID: "m1", replyText: "보낼 말"))
    try await repository.record(action(kind: .drafted, triggerMessageID: "m2", replyText: nil))
    try await repository.record(action(kind: .held, triggerMessageID: "m3"))

    #expect(try await repository.pendingDrafts(limit: 10).map(\.triggerMessageID) == ["m1"])
}

@Test
func aDraftThatWasAlreadySentIsNoLongerPending() async throws {
    let (repository, _, cleanup) = try makeRepository()
    defer { cleanup() }

    try await repository.record(action(kind: .drafted, triggerMessageID: "m1", replyText: "보낼 말"))
    try await repository.record(action(kind: .sent, triggerMessageID: "m1", replyText: "보낼 말"))

    #expect(try await repository.pendingDrafts(limit: 10).isEmpty)
}

/// Dismissing has to be recorded, not deleted: the timeline should still show
/// that TalkFlow proposed something and a person said no.
@Test
func dismissingKeepsTheDraftInHistoryButOutOfTheQueue() async throws {
    let (repository, _, cleanup) = try makeRepository()
    defer { cleanup() }
    try await repository.record(action(kind: .drafted, triggerMessageID: "m1", replyText: "보낼 말"))
    let pending = try await repository.pendingDrafts(limit: 10)

    try await repository.dismissDraft(id: pending[0].id)

    #expect(try await repository.pendingDrafts(limit: 10).isEmpty)
    #expect(try await repository.recent(limit: 10).contains { $0.kind == .dismissed })
    #expect(try await repository.recent(limit: 10).contains { $0.kind == .drafted })
}

// MARK: - 먼저 말 걸기

/// 초안만 is what an opener takes by default even in a room that delivers replies
/// on its own, so this list is the only way most of them ever get sent. An opener
/// missing from it is an opener nobody can act on.
@Test
func anOpenerWaitsForReviewBesideTheDraftsAndResolvesOnItsOwn() async throws {
    let (repository, _, cleanup) = try makeRepository()
    defer { cleanup() }
    let key = ConversationOpenerKey.make()

    try await repository.record(
        action(kind: .opened, triggerMessageID: key, replyText: "그거 결국 어떻게 됐어요?")
    )
    #expect(try await repository.pendingDrafts(limit: 10).count == 1)

    try await repository.record(
        action(kind: .sent, triggerMessageID: key, replyText: "그거 결국 어떻게 됐어요?")
    )
    #expect(try await repository.pendingDrafts(limit: 10).isEmpty)
}

/// The reason an opener carries a key of its own rather than the room's newest
/// message: a reply may already be waiting on that message, and two rows under
/// one trigger id are one row as far as this query is concerned. Sending the
/// opener would mark the reply handled.
@Test
func sendingAnOpenerDoesNotResolveAReplyWaitingInTheSameRoom() async throws {
    let (repository, _, cleanup) = try makeRepository()
    defer { cleanup() }
    let key = ConversationOpenerKey.make()

    try await repository.record(action(kind: .drafted, triggerMessageID: "m9", replyText: "네 좋아요"))
    try await repository.record(action(kind: .opened, triggerMessageID: key, replyText: "그때 그건 어떻게 됐어요?"))
    try await repository.record(action(kind: .sent, triggerMessageID: key, replyText: "그때 그건 어떻게 됐어요?"))

    let waiting = try await repository.pendingDrafts(limit: 10)

    #expect(waiting.count == 1)
    #expect(waiting.first?.triggerMessageID == "m9")
}

/// An opener the model passed on wrote no text, so it is a record rather than a
/// job. It must not sit in the review list waiting for a decision nobody can make.
@Test
func anOpenerTheModelPassedOnIsNotWaitingForAnybody() async throws {
    let (repository, _, cleanup) = try makeRepository()
    defer { cleanup() }

    try await repository.record(action(kind: .opened, triggerMessageID: ConversationOpenerKey.make()))

    #expect(try await repository.pendingDrafts(limit: 10).isEmpty)
    #expect(try await repository.recent(limit: 10).first?.kind == .opened)
}

/// An opener costs a model call, so it moves the cycle on. It is not a reply,
/// so it does not start the room's 최소 응답 간격 — a room that opened a subject
/// and then ignored whoever answered would be worse than one that never spoke.
@Test
func anOpenerCountsAsACallButNotAsAReply() async throws {
    let (repository, _, cleanup) = try makeRepository()
    defer { cleanup() }
    let moment = Date(timeIntervalSince1970: 1_700_000_000)

    try await repository.record(
        action(
            kind: .opened,
            triggerMessageID: ConversationOpenerKey.make(),
            replyText: "그거 결국 어떻게 됐어요?",
            at: moment
        )
    )

    #expect(try await repository.lastJudgementDate(chatRoomID: "room-1", accountFingerprint: account) == moment)
    #expect(try await repository.lastReplyDate(chatRoomID: "room-1", accountFingerprint: account) == nil)
}

/// The run of unanswered openers the gate bounds: `opened` rows after the moment
/// handed in, and nothing else. A reply or a hold in the same room is not an
/// opener and must not swell the count.
@Test
func openerCountCountsOnlyOpenedRowsAfterTheGivenMoment() async throws {
    let (repository, _, cleanup) = try makeRepository()
    defer { cleanup() }
    let base = Date(timeIntervalSince1970: 1_700_000_000)

    try await repository.record(action(kind: .opened, triggerMessageID: ConversationOpenerKey.make(), at: base.addingTimeInterval(60)))
    try await repository.record(action(kind: .opened, triggerMessageID: ConversationOpenerKey.make(), at: base.addingTimeInterval(120)))
    // A reply and a hold sit in the same room and window, and neither is an opener.
    try await repository.record(action(kind: .drafted, triggerMessageID: "m1", replyText: "네", at: base.addingTimeInterval(90)))
    try await repository.record(action(kind: .held, triggerMessageID: "m2", at: base.addingTimeInterval(100)))

    #expect(try await repository.openerCount(chatRoomID: "room-1", accountFingerprint: account, since: base) == 2)
}

/// The other side speaking is what resets the run: the moment moves forward to
/// their message, and the openers that came before it fall out of the window.
/// Strictly after, so an opener at the boundary instant is not counted twice.
@Test
func openerCountExcludesOpenersFromBeforeTheOtherSideLastSpoke() async throws {
    let (repository, _, cleanup) = try makeRepository()
    defer { cleanup() }
    let theyLastSpoke = Date(timeIntervalSince1970: 1_700_000_000)

    try await repository.record(action(kind: .opened, triggerMessageID: ConversationOpenerKey.make(), at: theyLastSpoke.addingTimeInterval(-600)))
    try await repository.record(action(kind: .opened, triggerMessageID: ConversationOpenerKey.make(), at: theyLastSpoke))
    try await repository.record(action(kind: .opened, triggerMessageID: ConversationOpenerKey.make(), at: theyLastSpoke.addingTimeInterval(600)))

    #expect(try await repository.openerCount(chatRoomID: "room-1", accountFingerprint: account, since: theyLastSpoke) == 1)
}

/// Keyed on room and account, so an opener in another room — or under another of
/// this Mac's accounts — is not part of this room's run.
@Test
func openerCountIsScopedToOneRoomAndAccount() async throws {
    let (repository, _, cleanup) = try makeRepository()
    defer { cleanup() }
    let base = Date(timeIntervalSince1970: 1_700_000_000)

    try await repository.record(action(kind: .opened, roomID: "room-1", triggerMessageID: ConversationOpenerKey.make(), at: base.addingTimeInterval(60)))
    try await repository.record(action(kind: .opened, roomID: "room-2", triggerMessageID: ConversationOpenerKey.make(), at: base.addingTimeInterval(60)))

    #expect(try await repository.openerCount(chatRoomID: "room-1", accountFingerprint: account, since: base) == 1)
    #expect(try await repository.openerCount(chatRoomID: "room-1", accountFingerprint: "other", since: base) == 0)
}

/// The durations have to survive the round trip through the column, because a
/// shape that encodes but does not decode loses every timing on the next launch
/// and looks exactly like a pipeline that stopped recording them.
@Test
func aRecordedTimelineReadsBackStageForStage() async throws {
    let (repository, _, cleanup) = try makeRepository()
    defer { cleanup() }
    let moment = Date(timeIntervalSince1970: 1_700_000_000)
    let timeline = ActionTimeline()
        .stamping(.detected, at: moment)
        .stamping(.modelRequested, at: moment.addingTimeInterval(6))
        .stamping(.modelAnswered, at: moment.addingTimeInterval(14), note: "사진 2장을 함께 보냅니다.")

    try await repository.record(
        AgentAction(
            accountFingerprint: account,
            chatRoomID: "room-1",
            kind: .drafted,
            triggerMessageID: "m1",
            replyText: "네 좋아요",
            detail: "테스트",
            contextMessageCount: 12,
            timeline: timeline,
            createdAt: moment
        )
    )

    let stored = try await repository.recent(limit: 1).first
    #expect(stored?.timeline == timeline)
    #expect(stored?.timeline.duration == 14)
    #expect(stored?.timeline.steps.last?.note == "사진 2장을 함께 보냅니다.")
}

/// Rows written before timings existed carry nothing, and must read as having
/// been untimed rather than as having taken no time. Every row already in this
/// database is one of those.
@Test
func anUntimedRowReadsBackAsHavingNoTimeline() async throws {
    let (repository, _, cleanup) = try makeRepository()
    defer { cleanup() }

    try await repository.record(action(kind: .held))

    #expect(try await repository.recent(limit: 1).first?.timeline.isEmpty == true)
}

/// Sub-second resolution survives the column.
///
/// Swift's `.iso8601` strategy writes whole seconds, and that rounded every
/// stamp inside one second onto the same instant — a draft answered and queued
/// milliseconds apart both read back as `:06.000`, and the pane had nothing left
/// to order them by.
@Test
func timesKeepTheirFractionOfASecondThroughTheColumn() async throws {
    let (repository, _, cleanup) = try makeRepository()
    defer { cleanup() }
    let moment = Date(timeIntervalSince1970: 1_700_000_000.25)
    let timeline = ActionTimeline()
        .stamping(.modelRequested, at: moment)
        .stamping(.modelAnswered, at: moment.addingTimeInterval(0.5))

    try await repository.record(
        AgentAction(
            accountFingerprint: account,
            chatRoomID: "room-1",
            kind: .drafted,
            triggerMessageID: "m1",
            detail: "테스트",
            timeline: timeline
        )
    )

    let stored = try await repository.recent(limit: 1).first?.timeline
    #expect(stored?.duration == 0.5)
    #expect(stored?.steps.first?.at == moment)
}
