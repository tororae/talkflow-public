import Foundation
import GRDB
import Testing
import TalkFlowDomain
@testable import TalkFlowInfrastructure

private let account = "katok-summaries"
private let directRoom = ChatRoom(id: "room-d", displayName: "가족", kind: .direct)
private let groupRoom = ChatRoom(id: "room-g", displayName: "프로젝트 팀", kind: .group)

private func makeDatabase() throws -> (TalkFlowDatabase, () -> Void) {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "talkflow-summaries-\(UUID().uuidString)/talkflow.sqlite")
    let database = try TalkFlowDatabase(fileURL: url)
    return (database, { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) })
}

private func migrationURL() -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "talkflow-summaries-migration-\(UUID().uuidString)/talkflow.sqlite")
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    return url
}

private func summary(
    _ text: String,
    room: ChatRoom = directRoom,
    isPinned: Bool = false,
    through: String? = "m40",
    covered: Int = 40
) -> ConversationSummary {
    ConversationSummary(
        accountFingerprint: account,
        chatRoomID: room.id,
        text: text,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        isPinned: isPinned,
        coveredThroughMessageID: through,
        coveredMessageCount: covered
    )
}

@Test
func aSummaryRoundTripsWithTheAnchorTheNextRefreshNeeds() async throws {
    let (database, cleanup) = try makeDatabase()
    defer { cleanup() }
    let repository = ConversationSummaryRepository(database: database)

    #expect(try await repository.summary(for: directRoom, accountFingerprint: account) == nil)

    try await repository.save(summary("이번 주 저녁 약속을 잡는 중."))
    let reloaded = try await repository.summary(for: directRoom, accountFingerprint: account)

    #expect(reloaded?.text == "이번 주 저녁 약속을 잡는 중.")
    #expect(reloaded?.coveredThroughMessageID == "m40")
    #expect(reloaded?.coveredMessageCount == 40)
    #expect(reloaded?.isPinned == false)
}

/// The flag decides whether the background sweep may touch the row, so losing it
/// on the way through the store would be a correction discarded by a round trip
/// rather than by a decision.
@Test
func aHandEditedNoteIsStillHandEditedAfterAReload() async throws {
    let (database, cleanup) = try makeDatabase()
    defer { cleanup() }
    let repository = ConversationSummaryRepository(database: database)

    try await repository.save(summary("前 직장 동료. 존댓말 유지.", isPinned: true))

    #expect(try await repository.summary(for: directRoom, accountFingerprint: account)?.isPinned == true)
}

/// The sweep reads every room's note in one query rather than once per room, so a
/// tick over a machine with dozens of rooms is one read plus arithmetic.
@Test
func everyRoomsNoteComesBackInOneRead() async throws {
    let (database, cleanup) = try makeDatabase()
    defer { cleanup() }
    let repository = ConversationSummaryRepository(database: database)

    try await repository.save(summary("가족방"))
    try await repository.save(summary("프로젝트 진행 중", room: groupRoom))

    let all = try await repository.summaries(accountFingerprint: account)

    #expect(all.count == 2)
    #expect(all[directRoom.id]?.text == "가족방")
    #expect(all[groupRoom.id]?.text == "프로젝트 진행 중")
    #expect(try await repository.summaries(accountFingerprint: "다른-계정").isEmpty)
}

/// 지우기 leaves nothing. The row is a written description of people the user
/// knows, and a blanked row that every future reader has to agree means absence is
/// not what the button says.
@Test
func clearingRemovesTheRowRatherThanEmptyingIt() async throws {
    let (database, cleanup) = try makeDatabase()
    defer { cleanup() }
    let repository = ConversationSummaryRepository(database: database)

    try await repository.save(summary("가족방"))
    try await repository.clear(chatRoomID: directRoom.id, accountFingerprint: account)

    #expect(try await repository.summary(for: directRoom, accountFingerprint: account) == nil)
    let rows = try await database.queue.read { db in
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM room_summaries") ?? -1
    }
    #expect(rows == 0)
}

/// A room configured before this existed keeps its note, and gets one. Unlike
/// photos and openers this widens nothing: the conversation it condenses is
/// already going to the provider on every reply in these rooms.
@Test
func roomsConfiguredBeforeTheUpgradeArriveRememberingTheirConversation() async throws {
    let url = migrationURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    try seedPolicyAtJudgementUnitSchema(at: url)

    let database = try TalkFlowDatabase(fileURL: url)
    let policy = try await RoomPolicyRepository(database: database)
        .policy(for: groupRoom, accountFingerprint: account)

    #expect(policy.remembersConversation)
    // Nothing else the user configured may be lost on the way through.
    #expect(policy.responseMode == .automatic)
    #expect(policy.deliveryMode == .always)
    #expect(policy.judgementInterval == JudgementInterval(measure: .messages, shortest: 5, longest: 15))
    #expect(policy.responseKeywords == ["달빛"])
    #expect(policy.conversationOpener == .delivers)
    #expect(policy.answeringConditionOverride?.text == "일정 얘기만")
}

/// The upgrade has to arrive with the table too, not only the column.
@Test
func theUpgradeBringsAnEmptySummaryTableRatherThanNone() async throws {
    let url = migrationURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    try seedPolicyAtJudgementUnitSchema(at: url)

    let database = try TalkFlowDatabase(fileURL: url)
    let repository = ConversationSummaryRepository(database: database)

    #expect(try await repository.summary(for: groupRoom, accountFingerprint: account) == nil)

    try await repository.save(summary("프로젝트 진행 중", room: groupRoom))

    #expect(try await repository.summary(for: groupRoom, accountFingerprint: account)?.text == "프로젝트 진행 중")
}

@Test
func theSettingRoundTripsWithTheRestOfTheRoomsPolicy() async throws {
    let (database, cleanup) = try makeDatabase()
    defer { cleanup() }
    let repository = RoomPolicyRepository(database: database)

    var policy = try await repository.policy(for: groupRoom, accountFingerprint: account)
    #expect(policy.remembersConversation)

    policy.responseMode = .automatic
    policy.remembersConversation = false
    try await repository.save(policy)

    #expect(try await repository.policy(for: groupRoom, accountFingerprint: account).remembersConversation == false)
}

/// The schema the shipped build writes today: every per-room setting exists except
/// the memory switch. The row sets the ones the migrations just before this one
/// added, so the upgrade has something to lose in each.
private func seedPolicyAtJudgementUnitSchema(at url: URL) throws {
    let queue = try DatabaseQueue(path: url.path)
    try TalkFlowDatabase.migrator.migrate(queue, upTo: "v13-room-judgement-interval-unit")
    try queue.write { db in
        try db.execute(
            sql: """
            INSERT INTO room_policies
                (account_fingerprint, chat_id, response_mode, interjection_chance,
                 delivery_mode, minimum_interval, judgement_interval,
                 judgement_interval_longest, judgement_interval_unit,
                 prefers_recent_human_reply, tags_recipient_by_name,
                 active_hours_limited, active_hours_start_minute,
                 active_hours_end_minute, reads_photos, conversation_opener,
                 conversation_opener_shortest, conversation_opener_longest,
                 response_keywords, answering_condition, uses_own_style,
                 style_tone, style_length, style_emoji_use, style_assertiveness)
            VALUES (?, ?, 'automatic', 40, 'always', 900, 5, 15, 'messages', 1, 1, 1, ?, ?, 1,
                    'delivers', 1800, 10800, ?, '일정 얘기만', 0,
                    '친근하고 간결하게', 'medium', 'some', 'balanced')
            """,
            arguments: [account, groupRoom.id, 9 * 60, 23 * 60, #"["달빛"]"#]
        )
    }
    try queue.close()
}
