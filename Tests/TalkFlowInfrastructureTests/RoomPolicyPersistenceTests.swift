import Foundation
import GRDB
import Testing
import TalkFlowDomain
@testable import TalkFlowInfrastructure

/// What the policy row stores today, column by column.
///
/// Written when `RoomPolicyRepository.save` named the same 48 columns in four
/// hand-maintained lists with the reader as a fifth, where a pair in the wrong
/// order compiled, saved, and put one room's numbers in another field. The lists
/// are now one `RoomPolicyRow.CodingKeys`, so that particular swap is a build
/// error — but these tests are what proved the replacement stores the same 48
/// values, and they are still the only thing that would notice a column quietly
/// dropping out of the row type. Whoever adds a room setting is told here which
/// field stopped surviving a save.

/// The INSERT path: a room saved for the first time comes back exactly as it was
/// written, in all 48 columns.
@Test
func everyRoomPolicyFieldSurvivesTheFirstSave() async throws {
    let (database, cleanup) = try makePolicyDatabase()
    defer { cleanup() }
    let repository = RoomPolicyRepository(database: database)

    let written = policySetOneWay(room: persistedRoom.id)
    try await repository.save(written)

    let read = try await repository.policy(for: persistedRoom, accountFingerprint: persistedAccount)

    expectEveryField(read, matches: written, "첫 저장(INSERT)")
}

/// The UPDATE path. GRDB derives `DO UPDATE SET` from the same coding keys as the
/// INSERT now, but a column that lands in one and not the other keeps the first
/// save's value forever and only a second save over the same room can show it —
/// so the second policy inverts every boolean and changes every number.
@Test
func everyRoomPolicyFieldIsRewrittenByASecondSaveOverTheSameRoom() async throws {
    let (database, cleanup) = try makePolicyDatabase()
    defer { cleanup() }
    let repository = RoomPolicyRepository(database: database)

    try await repository.save(policySetOneWay(room: persistedRoom.id))
    let rewritten = policySetTheOtherWay(room: persistedRoom.id)
    try await repository.save(rewritten)

    let read = try await repository.policy(for: persistedRoom, accountFingerprint: persistedAccount)

    expectEveryField(read, matches: rewritten, "덮어 저장(ON CONFLICT DO UPDATE)")
}

/// The nullable fields in both directions, because they fail differently. Filling
/// a null is what the INSERT does; clearing a filled one is only the `DO UPDATE
/// SET` list's job, and a column missing from it would leave the old text behind
/// while the screen showed the room following 설정 again.
@Test
func theNullableRoomPolicyFieldsClearAsWellAsFill() async throws {
    let (database, cleanup) = try makePolicyDatabase()
    defer { cleanup() }
    let repository = RoomPolicyRepository(database: database)

    var empty = policySetOneWay(room: persistedRoom.id)
    empty.answeringConditionOverride = nil
    empty.responseStyleOverride = nil
    empty.openerPromptHint = nil
    empty.responseKeywords = []
    empty.announcements.transitions = []

    // nil → 값
    try await repository.save(empty)
    let blank = try await repository.policy(for: persistedRoom, accountFingerprint: persistedAccount)
    expectEveryField(blank, matches: empty, "비운 채 첫 저장")
    #expect(blank.answeringConditionOverride == nil)
    #expect(blank.responseStyleOverride == nil)
    #expect(blank.openerPromptHint == nil)
    #expect(blank.responseKeywords.isEmpty)
    #expect(blank.announcements.transitions.isEmpty)

    let filled = policySetOneWay(room: persistedRoom.id)
    try await repository.save(filled)
    expectEveryField(
        try await repository.policy(for: persistedRoom, accountFingerprint: persistedAccount),
        matches: filled,
        "비운 뒤 채워 저장"
    )

    // 값 → nil
    try await repository.save(empty)
    let cleared = try await repository.policy(for: persistedRoom, accountFingerprint: persistedAccount)
    expectEveryField(cleared, matches: empty, "채운 뒤 다시 비워 저장")
    #expect(cleared.answeringConditionOverride == nil, "답변 조건 덮어쓰기가 지워지지 않았습니다")
    #expect(cleared.responseStyleOverride == nil, "응답 스타일 덮어쓰기가 지워지지 않았습니다")
    #expect(cleared.openerPromptHint == nil, "먼저 말 걸기 참고 지시가 지워지지 않았습니다")
    #expect(cleared.responseKeywords.isEmpty, "방 키워드가 지워지지 않았습니다")
    #expect(cleared.announcements.transitions.isEmpty, "상태 알림 전환이 지워지지 않았습니다")
}

/// The key is `(account_fingerprint, chat_id)`, so two rooms on one account and
/// one room id on two accounts are three separate policies. A read that bled
/// would hand one room another room's 전송 방식.
@Test
func twoRoomsAndTwoAccountsEachKeepTheirOwnPolicy() async throws {
    let (database, cleanup) = try makePolicyDatabase()
    defer { cleanup() }
    let repository = RoomPolicyRepository(database: database)

    let mine = policySetOneWay(room: persistedRoom.id)
    let myOtherRoom = policySetTheOtherWay(room: persistedOtherRoom.id)
    let sameRoomElsewhere = policySetTheOtherWay(
        room: persistedRoom.id,
        account: persistedOtherAccount
    )
    try await repository.save(mine)
    try await repository.save(myOtherRoom)
    try await repository.save(sameRoomElsewhere)

    expectEveryField(
        try await repository.policy(for: persistedRoom, accountFingerprint: persistedAccount),
        matches: mine,
        "방 1 / 계정 1"
    )
    expectEveryField(
        try await repository.policy(for: persistedOtherRoom, accountFingerprint: persistedAccount),
        matches: myOtherRoom,
        "방 2 / 계정 1"
    )
    expectEveryField(
        try await repository.policy(for: persistedRoom, accountFingerprint: persistedOtherAccount),
        matches: sameRoomElsewhere,
        "방 1 / 계정 2"
    )
}

/// The bulk read is a second trip through the same decoder for the same row
/// shape, and everything on screen at once comes from it. It has to agree with
/// the single-room read field for field, and it has to stay inside its account.
@Test
func theBulkReadDecodesEveryFieldTheSingleRoomReadDoes() async throws {
    let (database, cleanup) = try makePolicyDatabase()
    defer { cleanup() }
    let repository = RoomPolicyRepository(database: database)

    let mine = policySetOneWay(room: persistedRoom.id)
    let myOtherRoom = policySetTheOtherWay(room: persistedOtherRoom.id)
    try await repository.save(mine)
    try await repository.save(myOtherRoom)
    try await repository.save(policySetOneWay(room: persistedRoom.id, account: persistedOtherAccount))

    let all = try await repository.policies(accountFingerprint: persistedAccount)

    #expect(all.count == 2, "계정 하나에 방 둘을 저장했는데 \(all.count)개를 읽었습니다")
    expectEveryField(try #require(all[persistedRoom.id]), matches: mine, "묶음 읽기 / 방 1")
    expectEveryField(try #require(all[persistedOtherRoom.id]), matches: myOtherRoom, "묶음 읽기 / 방 2")
}

/// A row written by the schema before v29, then migrated: everything the user had
/// configured survives, and the seven opener columns that arrived after it take
/// the defaults the migration promised — no separate window, no repeats, 이어가기,
/// cadence running through the night, no hint.
@Test
func aPolicyRowWrittenBeforeTheOpenerColumnsSurvivesTheUpgrade() async throws {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "talkflow-policy-migration-\(UUID().uuidString)/talkflow.sqlite")
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    try seedFullyConfiguredPolicyAtLinkReadingSchema(at: url)

    let policy = try await RoomPolicyRepository(database: try TalkFlowDatabase(fileURL: url))
        .policy(for: persistedRoom, accountFingerprint: persistedAccount)

    expectEveryField(
        policy,
        matches: policyAsTheLinkReadingSchemaWroteIt(),
        "v28 스키마에서 쓴 행을 마이그레이션한 뒤"
    )
}

/// 판단 주기's unit is stored for the room's own cycle and for nothing else: 집중
/// 시간's cycle and 먼저 말 걸기's cadence have no unit column, so both read back
/// as seconds whatever they were saved as.
///
/// Pinned rather than fixed, and not currently reachable: no field or console
/// command offers 개 for either — 먼저 말 걸기 cannot be counted in messages by
/// construction (`JudgementIntervalInput.conversationOpener` has no `messages`
/// bounds), and 집중 시간's 판단 주기 has no editor at all. This test is here so
/// that whoever adds one finds out from a test rather than from a room that
/// started answering every 8 seconds instead of every 8 messages.
@Test
func neitherTheBurningCycleNorTheOpenerCadenceStoresItsUnit() async throws {
    let (database, cleanup) = try makePolicyDatabase()
    defer { cleanup() }
    let repository = RoomPolicyRepository(database: database)

    var policy = policySetOneWay(room: persistedRoom.id)
    policy.burning.judgementInterval = JudgementInterval(measure: .messages, shortest: 8, longest: 24)
    policy.conversationOpenerInterval = JudgementInterval(measure: .messages, shortest: 12, longest: 36)
    try await repository.save(policy)

    let read = try await repository.policy(for: persistedRoom, accountFingerprint: persistedAccount)

    #expect(read.burning.judgementInterval.measure == .seconds)
    #expect(read.burning.judgementInterval.shortest == 8)
    #expect(read.burning.judgementInterval.longest == 24)
    #expect(read.conversationOpenerInterval.measure == .seconds)
    #expect(read.conversationOpenerInterval.shortest == 12)
    #expect(read.conversationOpenerInterval.longest == 36)
    // The room's own cycle does keep its unit, which is the whole difference.
    #expect(read.judgementInterval.measure == .messages)
}

/// A row this build cannot read is one missing policy, not a failed load — and
/// the other rooms in the same read are unaffected.
///
/// Not the crash it used to be: `Row`'s subscripts decode with `try!`, so the row
/// this test builds took the old reader down with `GRDB/Row.swift:509: Fatal
/// error: 'try!' expression unexpectedly raised an error: could not decode
/// Optional<Double>` and signal 5. `RoomPolicyRow` throws instead and the
/// repository catches it per row, which is why the second room has to be here:
/// dropping every row whenever one is bad would pass a test that only saved one.
@Test
func anUnreadableRowReadsAsTheRoomsDefaultAndLeavesTheOtherRoomsAlone() async throws {
    let (database, cleanup) = try makePolicyDatabase()
    defer { cleanup() }
    let repository = RoomPolicyRepository(database: database)

    let healthy = policySetTheOtherWay(room: persistedOtherRoom.id)
    try await repository.save(policySetOneWay(room: persistedRoom.id))
    try await repository.save(healthy)
    try await corruptTheStoredInterval(of: persistedRoom.id, in: database)

    let read = try await repository.policy(for: persistedRoom, accountFingerprint: persistedAccount)
    #expect(read == .makeDefault(accountFingerprint: persistedAccount, room: persistedRoom))

    let all = try await repository.policies(accountFingerprint: persistedAccount)
    #expect(all[persistedRoom.id] == nil, "읽을 수 없는 행이 정책으로 올라왔습니다")
    #expect(all.count == 1, "한 행을 읽지 못해 나머지 방까지 사라졌습니다: \(all.count)개")
    expectEveryField(try #require(all[persistedOtherRoom.id]), matches: healthy, "손상된 행 옆의 방")
}

/// The write side of the same row, which is where the damage was.
///
/// A room that reads as `makeDefault` is a room the screen shows as 끔 with every
/// field at its default, and a default is a complete policy — so one 저장, or one
/// `!켬` from the console, wrote all 46 non-key columns and took the user's 답변
/// 조건, 참고 지시 and 키워드 with them. Unrecoverable, and nothing on screen or in
/// any log said so. The stored bytes are read back raw here because "the settings
/// survived" is the property that broke, and a decoded read cannot say it: the row
/// is the one thing in the file that will not decode.
@Test
func aSaveOverARowThatCannotBeReadIsRefusedAndLeavesTheStoredSettingsIntact() async throws {
    let (database, cleanup) = try makePolicyDatabase()
    defer { cleanup() }
    let repository = RoomPolicyRepository(database: database)

    try await repository.save(policySetOneWay(room: persistedRoom.id))
    try await corruptTheStoredInterval(of: persistedRoom.id, in: database)

    // What the room screen would send after one flipped switch: the default it
    // was shown, with 응답 turned on.
    var overwrite = RoomPolicy.makeDefault(accountFingerprint: persistedAccount, room: persistedRoom)
    overwrite.responseMode = .automatic

    await #expect(throws: RoomPolicySaveRefusal(chatRoomID: persistedRoom.id)) {
        try await repository.save(overwrite)
    }

    let stored = try #require(try await storedColumns(of: persistedRoom.id, in: database))
    #expect(stored["answering_condition"] == "이 방은 급한 것만".databaseValue)
    #expect(stored["opener_prompt_hint"] == "요즘 하는 프로젝트 얘기 꺼내".databaseValue)
    #expect(stored["response_keywords"] == #"["코드명","dalbit-1"]"#.databaseValue)
    #expect(stored["style_tone"] == "짧고 무뚝뚝하게".databaseValue)
    #expect(stored["announcement_transitions"] == #"["activeHoursClosed","burningStarted"]"#.databaseValue)
    #expect(stored["response_mode"] == ResponseMode.detectOnly.rawValue.databaseValue, "응답 방식이 덮어써졌습니다")
    #expect(stored["opener_repeat_limit"] == 3.databaseValue)
    #expect(stored["interjection_chance"] == 37.databaseValue)
    #expect(stored["uses_own_style"] == true.databaseValue)
    #expect(stored["burning_cooldown_longest"] == 7_777.0.databaseValue)
    // The corrupted column is left exactly as it was too: refusing is not repairing.
    #expect(stored["minimum_interval"] == "숫자가 아님".databaseValue)
}

/// The refusal is only for a row that exists and cannot be read. A room with no
/// row has nothing to protect, and a room whose row reads fine is saved over as
/// always — otherwise the guard would have made the settings screen useless.
@Test
func theRefusalDoesNotStandInTheWayOfAFirstSaveOrAnOrdinarySave() async throws {
    let (database, cleanup) = try makePolicyDatabase()
    defer { cleanup() }
    let repository = RoomPolicyRepository(database: database)

    // No row at all: nothing to refuse.
    let first = policySetOneWay(room: persistedRoom.id)
    try await repository.save(first)
    expectEveryField(
        try await repository.policy(for: persistedRoom, accountFingerprint: persistedAccount),
        matches: first,
        "행이 없던 방의 첫 저장"
    )

    // A readable row: saved over.
    let second = policySetTheOtherWay(room: persistedRoom.id)
    try await repository.save(second)
    expectEveryField(
        try await repository.policy(for: persistedRoom, accountFingerprint: persistedAccount),
        matches: second,
        "읽을 수 있는 행 위의 저장"
    )

    // A corrupt row in one room does not stop another room from being saved: the
    // guard is keyed on the row being written, not on the table being clean.
    try await corruptTheStoredInterval(of: persistedRoom.id, in: database)
    let elsewhere = policySetOneWay(room: persistedOtherRoom.id)
    try await repository.save(elsewhere)
    expectEveryField(
        try await repository.policy(for: persistedOtherRoom, accountFingerprint: persistedAccount),
        matches: elsewhere,
        "손상된 행 옆 방의 저장"
    )
}

/// `room_policies` has exactly one uniqueness constraint, and the writer depends
/// on it.
///
/// GRDB's `upsert` emits `ON CONFLICT` with no target, so *any* uniqueness
/// violation takes the `DO UPDATE SET` branch. With only the primary key there is
/// nothing else to catch. Add a `UNIQUE` index to this table and that stops being
/// true in the worst way: where the hand-written `ON CONFLICT(account_fingerprint,
/// chat_id)` raised `SQLite error 19: UNIQUE constraint failed`, the untargeted
/// clause silently updates the row that collided — one room quietly wearing
/// another room's 46 columns, and the room that was being saved having no row at
/// all. GRDB's plain `upsert` takes no conflict target, so this is a test rather
/// than a fix: whoever adds the index finds out here.
@Test
func roomPoliciesHasNoUniquenessConstraintBesidesItsPrimaryKey() async throws {
    let (database, cleanup) = try makePolicyDatabase()
    defer { cleanup() }

    let unique = try await database.queue.read { db in
        try db.indexes(on: "room_policies")
            .filter(\.isUnique)
            .map { "\($0.name) \($0.columns)" }
    }

    #expect(unique == ["sqlite_autoindex_room_policies_1 [\"account_fingerprint\", \"chat_id\"]"])
}

/// Text where a `DOUBLE NOT NULL` column's seconds belong. The column keeps its
/// constraint — the value is there and it is not null — and no decoder can turn it
/// into a number, which is every unreadable row in one line.
private func corruptTheStoredInterval(of chatID: String, in database: TalkFlowDatabase) async throws {
    try await database.queue.write { db in
        try db.execute(
            sql: "UPDATE room_policies SET minimum_interval = '숫자가 아님' WHERE chat_id = ?",
            arguments: [chatID]
        )
    }
}

/// Every column of one row as the value SQLite is holding, read without going
/// through the row type.
///
/// `DatabaseValue` rather than text, so the comparison is over the storage class
/// too: 3 as an integer is not 3 as a string, and a guard that rewrote the row
/// with the same numbers in different types would be a change worth failing over.
private func storedColumns(
    of chatID: String,
    in database: TalkFlowDatabase
) async throws -> [String: DatabaseValue]? {
    try await database.queue.read { db in
        try Row.fetchOne(
            db,
            sql: "SELECT * FROM room_policies WHERE chat_id = ?",
            arguments: [chatID]
        )
        .map { row in
            row.reduce(into: [:]) { columns, pair in
                columns[pair.0] = pair.1
            }
        }
    }
}

/// What the row above says the user had configured. Every value differs from the
/// column's default, so a migration that dropped one would show.
private func policyAsTheLinkReadingSchemaWroteIt() -> RoomPolicy {
    RoomPolicy(
        accountFingerprint: persistedAccount,
        chatRoomID: persistedRoom.id,
        responseMode: .mentionOnly,
        interjectionChance: InterjectionChance(percent: 33),
        deliveryMode: .autoSendWhenIdle,
        minimumInterval: 777,
        judgementInterval: JudgementInterval(measure: .messages, shortest: 12, longest: 48),
        activeHours: ReplyActiveHours(isLimited: true, startMinute: 505, endMinute: 1_211),
        readsPhotos: true,
        webSearch: true,
        readsLinks: true,
        conversationOpener: .draftOnly,
        conversationOpenerInterval: JudgementInterval(shortest: 1_234, longest: 5_678),
        // The v29 columns, which this row predates.
        conversationOpenerHours: .always,
        openerRepeatLimit: 0,
        openerRepeatTopic: .carryOn,
        openerCadencePausesOutsideHours: false,
        openerPromptHint: nil,
        responseKeywords: ["달빛", "dalbit"],
        answeringConditionOverride: AnsweringCondition("이 방은 일정만"),
        responseStyleOverride: ResponseStyle(
            tone: "무뚝뚝하게",
            length: .long,
            emojiUse: .frequent,
            assertiveness: .forward
        ),
        remembersConversation: false,
        answersReplies: false,
        burning: BurningMode(
            isEnabled: true,
            chance: InterjectionChance(percent: 44),
            duration: JudgementInterval(shortest: 601, longest: 1_501),
            cooldown: JudgementInterval(shortest: 7_201, longest: 21_601),
            interjectionChance: InterjectionChance(percent: 91),
            minimumInterval: 65,
            judgementInterval: JudgementInterval(shortest: 21, longest: 87)
        ),
        announcements: StateAnnouncements(
            transitions: [.activeHoursOpened],
            withinRecentConversation: 999,
            delivery: .delivers
        ),
        remembersPeople: true
    )
}

/// The schema the shipped build wrote before 먼저 말 걸기 gained its own hours:
/// every column the current writer names except those seven exists, and this row
/// fills all of them so the upgrade has something to lose in each one.
private func seedFullyConfiguredPolicyAtLinkReadingSchema(at url: URL) throws {
    let queue = try DatabaseQueue(path: url.path)
    try TalkFlowDatabase.migrator.migrate(queue, upTo: "v28-room-link-reading")
    try queue.write { db in
        try db.execute(
            sql: """
            INSERT INTO room_policies
                (account_fingerprint, chat_id, response_mode, interjection_chance,
                 delivery_mode, minimum_interval, judgement_interval,
                 judgement_interval_longest, judgement_interval_unit,
                 prefers_recent_human_reply, tags_recipient_by_name,
                 active_hours_limited, active_hours_start_minute,
                 active_hours_end_minute, reads_photos, web_search, reads_links,
                 conversation_opener, conversation_opener_shortest,
                 conversation_opener_longest, response_keywords,
                 answering_condition, uses_own_style, style_tone, style_length,
                 style_emoji_use, style_assertiveness, remembers_conversation,
                 answers_replies, burning_enabled, burning_chance,
                 burning_duration_shortest, burning_duration_longest,
                 burning_cooldown_shortest, burning_cooldown_longest,
                 burning_interjection_chance, burning_minimum_interval,
                 burning_judgement_interval, burning_judgement_interval_longest,
                 announcement_transitions, announcement_recent_window,
                 announcement_delivery, remembers_people)
            VALUES (?, ?, 'mentionOnly', 33,
                    'autoSendWhenIdle', 777, 12,
                    48, 'messages',
                    1, 1,
                    1, 505,
                    1211, 1, 1, 1,
                    'draftOnly', 1234,
                    5678, ?,
                    '이 방은 일정만', 1, '무뚝뚝하게', 'long',
                    'frequent', 'forward', 0,
                    0, 1, 44,
                    601, 1501,
                    7201, 21601,
                    91, 65,
                    21, 87,
                    ?, 999,
                    'delivers', 1)
            """,
            arguments: [
                persistedAccount,
                persistedRoom.id,
                #"["달빛","dalbit"]"#,
                #"["activeHoursOpened"]"#
            ]
        )
    }
    try queue.close()
}
