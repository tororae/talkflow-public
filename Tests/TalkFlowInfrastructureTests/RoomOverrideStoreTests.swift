import Foundation
import GRDB
import Testing
import TalkFlowDomain
@testable import TalkFlowInfrastructure

private let account = "katok-overrides"
private let groupRoom = ChatRoom(id: "room-g", displayName: "프로젝트 팀", kind: .group)

private func makeDatabase() throws -> (TalkFlowDatabase, () -> Void) {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "talkflow-overrides-\(UUID().uuidString)/talkflow.sqlite")
    let database = try TalkFlowDatabase(fileURL: url)
    return (database, { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) })
}

private func migrationURL() -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "talkflow-overrides-migration-\(UUID().uuidString)/talkflow.sqlite")
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    return url
}

/// The enum's three words map onto two numbers, because only one of them meant
/// something the model could not do for itself: 꺼짐 kept a message from ever
/// being asked about. 낮음 and 보통 both asked every time — they differed only in
/// the wording of the prompt, and for months not even in that.
@Test
func theOldLevelsMapOntoZeroAndOneHundred() async throws {
    for (level, expected) in [("off", InterjectionChance.never), ("low", .always), ("medium", .always)] {
        let url = migrationURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        try seedPolicyAtOpenerSchema(at: url, spontaneousLevel: level)

        let policy = try await RoomPolicyRepository(database: try TalkFlowDatabase(fileURL: url))
            .policy(for: groupRoom, accountFingerprint: account)

        #expect(policy.interjectionChance == expected, "\(level) mapped to \(policy.interjectionChance.summary)")
    }
}

/// Nothing else the user set may be lost on the way through, including the
/// settings that arrived in the migrations just before this one.
@Test
func theUpgradeKeepsEverythingElseTheRoomWasConfiguredWith() async throws {
    let url = migrationURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    try seedPolicyAtOpenerSchema(at: url, spontaneousLevel: "medium")

    let policy = try await RoomPolicyRepository(database: try TalkFlowDatabase(fileURL: url))
        .policy(for: groupRoom, accountFingerprint: account)

    #expect(policy.responseMode == .automatic)
    #expect(policy.deliveryMode == .always)
    #expect(policy.minimumInterval == 900)
    #expect(policy.judgementInterval == JudgementInterval(shortest: 60, longest: 600))
    #expect(policy.activeHours == ReplyActiveHours(isLimited: true, startMinute: 9 * 60, endMinute: 23 * 60))
    #expect(policy.readsPhotos)
    #expect(policy.responseKeywords == ["달빛"])
    #expect(policy.conversationOpener == .delivers)
}

/// The v29 opener settings survive a save and read back exactly — the check that
/// the widened INSERT columns, their value bindings, and the row reader all still
/// line up after seven columns were added to the middle of a full-row upsert.
@Test
func theOpenerSettingsSurviveASaveAndReadBack() async throws {
    let (database, cleanup) = try makeDatabase()
    defer { cleanup() }
    let repository = RoomPolicyRepository(database: database)

    var policy = RoomPolicy.makeDefault(accountFingerprint: account, room: groupRoom)
    policy.conversationOpener = .delivers
    policy.conversationOpenerHours = ReplyActiveHours(isLimited: true, startMinute: 600, endMinute: 1320)
    policy.openerRepeatLimit = 3
    policy.openerRepeatTopic = .fresh
    policy.openerCadencePausesOutsideHours = true
    policy.openerPromptHint = "요즘 하는 프로젝트 얘기 꺼내"
    try await repository.save(policy)

    let loaded = try await repository.policy(for: groupRoom, accountFingerprint: account)
    #expect(loaded.conversationOpenerHours == ReplyActiveHours(isLimited: true, startMinute: 600, endMinute: 1320))
    #expect(loaded.openerRepeatLimit == 3)
    #expect(loaded.openerRepeatTopic == .fresh)
    #expect(loaded.openerCadencePausesOutsideHours)
    #expect(loaded.openerPromptHint == "요즘 하는 프로젝트 얘기 꺼내")
}

/// Both overrides arrive as "follow 설정". A room configured before they existed
/// has been answering in the global style all along, and freezing a copy of
/// today's global into it would turn every later edit of 설정 into a setting that
/// stopped working.
@Test
func aRoomConfiguredBeforeOverridesExistedStillFollowsTheGlobalSettings() async throws {
    let url = migrationURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    try seedPolicyAtOpenerSchema(at: url, spontaneousLevel: "medium")

    let policy = try await RoomPolicyRepository(database: try TalkFlowDatabase(fileURL: url))
        .policy(for: groupRoom, accountFingerprint: account)
    let global = ResponseStyle(tone: "정중하게", length: .long)

    #expect(policy.answeringConditionOverride == nil)
    #expect(policy.responseStyleOverride == nil)
    #expect(policy.responseStyle(global: global) == global)
    #expect(policy.answeringCondition(global: AnsweringCondition("일정 얘기만")).text == "일정 얘기만")
}

@Test
func theChanceAndBothOverridesRoundTripThroughTheStore() async throws {
    let (database, cleanup) = try makeDatabase()
    defer { cleanup() }
    let repository = RoomPolicyRepository(database: database)

    var policy = try await repository.policy(for: groupRoom, accountFingerprint: account)
    policy.responseMode = .automatic
    policy.interjectionChance = InterjectionChance(percent: 40)
    policy.answeringConditionOverride = AnsweringCondition("이 방은 급한 것만")
    policy.responseStyleOverride = ResponseStyle(
        tone: "짧고 무뚝뚝하게",
        length: .short,
        emojiUse: .none,
        assertiveness: .forward
    )
    try await repository.save(policy)

    let reloaded = try await repository.policy(for: groupRoom, accountFingerprint: account)

    #expect(reloaded == policy)
    #expect(reloaded.interjectionChance.percent == 40)
    #expect(reloaded.usesOwnResponseStyle)
}

/// An override that is empty is not the same as no override. "이 방은 조건 없이
/// 판단해" is a thing to want in a room where the global condition is too narrow,
/// and a store that read a blank as "follow the global" would make it impossible
/// to say.
@Test
func anEmptyConditionOverrideSurvivesAsAnOverride() async throws {
    let (database, cleanup) = try makeDatabase()
    defer { cleanup() }
    let repository = RoomPolicyRepository(database: database)

    var policy = try await repository.policy(for: groupRoom, accountFingerprint: account)
    policy.responseMode = .automatic
    policy.answeringConditionOverride = .empty
    try await repository.save(policy)

    let reloaded = try await repository.policy(for: groupRoom, accountFingerprint: account)

    #expect(reloaded.usesOwnAnsweringCondition)
    #expect(reloaded.answeringCondition(global: AnsweringCondition("일정 얘기만")).isEmpty)
}

/// Turning the style override off has to put the room back on the global one
/// rather than leaving the values it was holding in force.
@Test
func clearingTheStyleOverridePutsTheRoomBackOnTheGlobalStyle() async throws {
    let (database, cleanup) = try makeDatabase()
    defer { cleanup() }
    let repository = RoomPolicyRepository(database: database)

    var policy = try await repository.policy(for: groupRoom, accountFingerprint: account)
    policy.responseMode = .automatic
    policy.responseStyleOverride = ResponseStyle(tone: "짧고 무뚝뚝하게")
    try await repository.save(policy)

    policy.responseStyleOverride = nil
    try await repository.save(policy)

    let reloaded = try await repository.policy(for: groupRoom, accountFingerprint: account)

    #expect(reloaded.responseStyleOverride == nil)
    #expect(reloaded.responseStyle(global: ResponseStyle(tone: "정중하게")).tone == "정중하게")
}

/// The global condition shares the single row the global style lives in, and the
/// two are edited on the same screen. A writer that rewrote the whole row would
/// have whichever saved last quietly undo the other.
@Test
func theGlobalConditionAndStyleDoNotOverwriteEachOther() async throws {
    let (database, cleanup) = try makeDatabase()
    defer { cleanup() }
    let repository = AppSettingsRepository(database: database)

    #expect(try await repository.answeringCondition().isEmpty)

    try await repository.save(AnsweringCondition("일정 얘기 위주로"))
    try await repository.save(ResponseStyle(tone: "정중하게", responseKeywords: ["달빛"]))

    #expect(try await repository.answeringCondition().text == "일정 얘기 위주로")
    #expect(try await repository.responseStyle().tone == "정중하게")

    try await repository.save(AnsweringCondition("급한 것만"))

    #expect(try await repository.responseStyle().responseKeywords == ["달빛"])
    #expect(try await repository.answeringCondition().text == "급한 것만")
}

/// The schema the shipped build writes today: every per-room setting exists
/// except the chance and the two overrides. The row sets all of them, so the
/// upgrade has something to lose in each column.
private func seedPolicyAtOpenerSchema(at url: URL, spontaneousLevel: String) throws {
    let queue = try DatabaseQueue(path: url.path)
    try TalkFlowDatabase.migrator.migrate(queue, upTo: "v11-room-conversation-opener")
    try queue.write { db in
        try db.execute(
            sql: """
            INSERT INTO room_policies
                (account_fingerprint, chat_id, response_mode, spontaneous_level,
                 delivery_mode, minimum_interval, judgement_interval,
                 judgement_interval_longest, prefers_recent_human_reply,
                 tags_recipient_by_name, active_hours_limited,
                 active_hours_start_minute, active_hours_end_minute, reads_photos,
                 conversation_opener, conversation_opener_shortest,
                 conversation_opener_longest, response_keywords)
            VALUES (?, ?, 'automatic', ?, 'always', 900, 60, 600, 1, 1, 1, ?, ?, 1,
                    'delivers', 1800, 10800, ?)
            """,
            arguments: [
                account,
                groupRoom.id,
                spontaneousLevel,
                9 * 60,
                23 * 60,
                #"["달빛"]"#
            ]
        )
    }
    try queue.close()
}
