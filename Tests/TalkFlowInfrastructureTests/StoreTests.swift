import Foundation
import GRDB
import Testing
import TalkFlowDomain
@testable import TalkFlowInfrastructure

private let account = "katok-test"
private let groupRoom = ChatRoom(id: "room-g", displayName: "프로젝트 팀", kind: .group)

private func makeDatabase() throws -> (TalkFlowDatabase, () -> Void) {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "talkflow-store-\(UUID().uuidString)/talkflow.sqlite")
    let database = try TalkFlowDatabase(fileURL: url)
    return (database, { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) })
}

@Test
func anUnconfiguredRoomReadsBackAsTheSilentDefault() async throws {
    let (database, cleanup) = try makeDatabase()
    defer { cleanup() }

    let policy = try await RoomPolicyRepository(database: database)
        .policy(for: groupRoom, accountFingerprint: account)

    #expect(policy.responseMode == .off)
    #expect(policy.chatRoomID == groupRoom.id)
    #expect(policy.accountFingerprint == account)
}

@Test
func aSavedPolicySurvivesReopeningTheStore() async throws {
    let (database, cleanup) = try makeDatabase()
    defer { cleanup() }
    let repository = RoomPolicyRepository(database: database)

    var policy = try await repository.policy(for: groupRoom, accountFingerprint: account)
    policy.responseMode = .mentionOnly
    policy.interjectionChance = InterjectionChance(percent: 40)
    policy.deliveryMode = .autoSendWhenIdle
    policy.minimumInterval = 900
    policy.judgementInterval = JudgementInterval(shortest: 60, longest: 600)
    policy.activeHours = ReplyActiveHours(isLimited: true, startMinute: 22 * 60, endMinute: 2 * 60)
    policy.readsPhotos = true
    policy.responseKeywords = ["달빛", "dalbit"]
    try await repository.save(policy)

    let reloaded = try await repository.policy(for: groupRoom, accountFingerprint: account)

    #expect(reloaded == policy)
}

/// A room nobody gave extra words to answers to the account's own name and the
/// global keywords, so its own list starts empty rather than at some default.
@Test
func aRoomStartsWithNoKeywordsOfItsOwn() async throws {
    let (database, cleanup) = try makeDatabase()
    defer { cleanup() }
    let repository = RoomPolicyRepository(database: database)

    var policy = try await repository.policy(for: groupRoom, accountFingerprint: account)
    #expect(policy.responseKeywords.isEmpty)

    policy.responseMode = .mentionOnly
    try await repository.save(policy)

    #expect(try await repository.policy(for: groupRoom, accountFingerprint: account).responseKeywords.isEmpty)
}

/// The rooms configured before per-room keywords existed have to come back
/// exactly as they were, with an empty list rather than a lost setting. Their
/// behaviour is unchanged by the upgrade: they keep the global keywords, and
/// they gain the account's own name without anyone registering it.
@Test
func aRoomConfiguredBeforeItsOwnKeywordsExistedComesBackWithNone() async throws {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "talkflow-migration-\(UUID().uuidString)/talkflow.sqlite")
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    try seedPolicyAtPhotoSchema(at: url)

    let policy = try await RoomPolicyRepository(database: try TalkFlowDatabase(fileURL: url))
        .policy(for: groupRoom, accountFingerprint: account)

    #expect(policy.responseKeywords.isEmpty)
    #expect(policy.responseMode == .mentionOnly)
    #expect(policy.interjectionChance == .always)
    #expect(policy.deliveryMode == .always)
    #expect(policy.minimumInterval == 900)
    #expect(policy.activeHours == ReplyActiveHours(isLimited: true, startMinute: 9 * 60, endMinute: 23 * 60))
    #expect(policy.readsPhotos == true)
}

/// The rooms the user configured before these settings existed are the whole
/// point of a migration: they have to come back exactly as they were, taking the
/// new columns' defaults rather than losing anything.
@Test
func aRoomConfiguredBeforeTaggingAndHoursExistedSurvivesTheUpgrade() async throws {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "talkflow-migration-\(UUID().uuidString)/talkflow.sqlite")
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    try seedPolicyAtOlderSchema(at: url)

    let policy = try await RoomPolicyRepository(database: try TalkFlowDatabase(fileURL: url))
        .policy(for: groupRoom, accountFingerprint: account)

    #expect(policy.responseMode == .automatic)
    #expect(policy.interjectionChance == .always)
    #expect(policy.deliveryMode == .always)
    #expect(policy.minimumInterval == 0)
    #expect(policy.activeHours == .always)
    #expect(policy.readsPhotos == false)
}

/// Reading photos widens what leaves the Mac, so the rooms that were already
/// configured have to come back with it off — and with everything the user did
/// set still exactly as they set it.
@Test
func aRoomConfiguredBeforePhotoReadingExistedComesBackWithItOff() async throws {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "talkflow-migration-\(UUID().uuidString)/talkflow.sqlite")
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    try seedPolicyAtTaggingSchema(at: url)

    let policy = try await RoomPolicyRepository(database: try TalkFlowDatabase(fileURL: url))
        .policy(for: groupRoom, accountFingerprint: account)

    #expect(policy.readsPhotos == false)
    #expect(policy.responseMode == .automatic)
    #expect(policy.interjectionChance == .always)
    #expect(policy.deliveryMode == .always)
    #expect(policy.minimumInterval == 0)
    #expect(policy.activeHours == ReplyActiveHours(isLimited: true, startMinute: 9 * 60, endMinute: 23 * 60))
}

/// The interval is typed now rather than chosen from a menu, so a number nobody
/// would have put in a menu — and a range, which a menu cannot express at all —
/// has to survive the trip to disk and back.
@Test
func aTypedJudgementRangeRoundTripsThroughTheStore() async throws {
    let (database, cleanup) = try makeDatabase()
    defer { cleanup() }
    let repository = RoomPolicyRepository(database: database)

    guard case let .success(typed) = JudgementIntervalInput.judgement.interval(
        shortest: "10",
        longest: "300",
        unit: .seconds
    ) else {
        Issue.record("10초~300초는 받아들여야 합니다")
        return
    }

    var policy = try await repository.policy(for: groupRoom, accountFingerprint: account)
    policy.responseMode = .automatic
    policy.judgementInterval = typed
    try await repository.save(policy)

    let reloaded = try await repository.policy(for: groupRoom, accountFingerprint: account)

    #expect(reloaded.judgementInterval == JudgementInterval(shortest: 10, longest: 300))
    #expect(reloaded.judgesInBatches)
}

/// The two numbers mean nothing without the unit beside them. A cycle saved as
/// 5개~15개 that came back as five to fifteen seconds would be a room answering
/// every few seconds because of an upgrade.
@Test
func aCycleCountedInMessagesRoundTripsAsMessages() async throws {
    let (database, cleanup) = try makeDatabase()
    defer { cleanup() }
    let repository = RoomPolicyRepository(database: database)

    guard case let .success(typed) = JudgementIntervalInput.judgement.interval(
        shortest: "5",
        longest: "15",
        unit: .messages
    ) else {
        Issue.record("5개~15개는 받아들여야 합니다")
        return
    }

    var policy = try await repository.policy(for: groupRoom, accountFingerprint: account)
    policy.responseMode = .automatic
    policy.judgementInterval = typed
    try await repository.save(policy)

    let reloaded = try await repository.policy(for: groupRoom, accountFingerprint: account)

    #expect(reloaded.judgementInterval == JudgementInterval(measure: .messages, shortest: 5, longest: 15))
    #expect(reloaded.judgementInterval.countsMessages)
    #expect(reloaded.judgesInBatches)

    // And back again: switching a room to a stretch of time has to clear the unit
    // as well as the numbers, or the room keeps counting messages it no longer
    // shows on screen.
    policy.judgementInterval = JudgementInterval(fixed: 300)
    try await repository.save(policy)

    #expect(try await repository.policy(for: groupRoom, accountFingerprint: account)
        .judgementInterval == JudgementInterval(fixed: 300))
}

/// Counting in messages is a way of judging less often, and a room the user set up
/// to answer each message may not start holding them back because an upgrade
/// added a second unit. Every room already configured keeps the unit its numbers
/// have always been in — and the rooms on 즉시 keep no numbers at all.
@Test
func roomsConfiguredBeforeTheCountExistedKeepJudgingTheWayTheyDid() async throws {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "talkflow-migration-\(UUID().uuidString)/talkflow.sqlite")
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    try seedPoliciesAtInterjectionSchema(at: url)

    let policies = try await RoomPolicyRepository(database: try TalkFlowDatabase(fileURL: url))
        .policies(accountFingerprint: account)

    #expect(policies["room-immediate"]?.judgementInterval == .immediate)
    #expect(policies["room-immediate"]?.judgesInBatches == false)
    #expect(policies["room-timed"]?.judgementInterval == JudgementInterval(shortest: 60, longest: 600))
    #expect(policies["room-timed"]?.judgementInterval.countsMessages == false)
}

/// A room configured before ranges existed kept one number, and it has to come
/// back as the fixed interval it was rather than as a range from that number to
/// nothing.
@Test
func aRoomConfiguredBeforeRangesExistedComesBackAsAFixedInterval() async throws {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "talkflow-migration-\(UUID().uuidString)/talkflow.sqlite")
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    try seedPolicyAtFixedIntervalSchema(at: url)

    let policy = try await RoomPolicyRepository(database: try TalkFlowDatabase(fileURL: url))
        .policy(for: groupRoom, accountFingerprint: account)

    #expect(policy.judgementInterval == JudgementInterval(fixed: 600))
    #expect(policy.judgementInterval.isFixed)
    #expect(policy.interjectionChance == .always)
}

/// Judging in batches changes when a room answers, so a room the user set up to
/// answer each message has to keep doing that across the upgrade rather than
/// silently start holding messages back.
@Test
func aRoomConfiguredBeforeBatchedJudgementKeepsAnsweringEachMessage() async throws {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "talkflow-migration-\(UUID().uuidString)/talkflow.sqlite")
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    try seedPolicyAtKeywordSchema(at: url)

    let policy = try await RoomPolicyRepository(database: try TalkFlowDatabase(fileURL: url))
        .policy(for: groupRoom, accountFingerprint: account)

    #expect(policy.judgementInterval == .immediate)
    #expect(policy.judgesInBatches == false)
    #expect(policy.responseMode == .automatic)
    #expect(policy.interjectionChance == .always)
    #expect(policy.minimumInterval == 900)
    #expect(policy.responseKeywords == ["달빛"])
}

/// The schema the shipped build writes today: two rooms, one judging every
/// message and one on a cycle of seconds, which is every shape a room in the file
/// can currently be in.
private func seedPoliciesAtInterjectionSchema(at url: URL) throws {
    let queue = try DatabaseQueue(path: url.path)
    try TalkFlowDatabase.migrator.migrate(queue, upTo: "v12-interjection-chance-and-room-overrides")
    try queue.write { db in
        for (chatID, shortest, longest) in [("room-immediate", 0, 0), ("room-timed", 60, 600)] {
            try db.execute(
                sql: """
                INSERT INTO room_policies
                    (account_fingerprint, chat_id, response_mode, interjection_chance,
                     delivery_mode, minimum_interval, judgement_interval,
                     judgement_interval_longest, prefers_recent_human_reply,
                     tags_recipient_by_name, active_hours_limited,
                     active_hours_start_minute, active_hours_end_minute, reads_photos,
                     conversation_opener, conversation_opener_shortest,
                     conversation_opener_longest, response_keywords, uses_own_style,
                     style_tone, style_length, style_emoji_use, style_assertiveness)
                VALUES (?, ?, 'automatic', 100, 'always', 900, ?, ?, 1, 1, 0, 0, 0, 1,
                        'off', 1800, 10800, '[]', 0, '친근하게', 'medium', 'some', 'balanced')
                """,
                arguments: [account, chatID, shortest, longest]
            )
        }
    }
    try queue.close()
}

/// The schema that had an interval but only one number for it.
private func seedPolicyAtFixedIntervalSchema(at url: URL) throws {
    let queue = try DatabaseQueue(path: url.path)
    try TalkFlowDatabase.migrator.migrate(queue, upTo: "v8-pending-send-trigger-sender")
    try queue.write { db in
        try db.execute(
            sql: """
            INSERT INTO room_policies
                (account_fingerprint, chat_id, response_mode, spontaneous_level,
                 delivery_mode, minimum_interval, judgement_interval,
                 prefers_recent_human_reply,
                 tags_recipient_by_name, active_hours_limited,
                 active_hours_start_minute, active_hours_end_minute, reads_photos,
                 response_keywords)
            VALUES (?, ?, 'automatic', 'low', 'always', 900, 600, 1, 1, 0, ?, ?, 1, ?)
            """,
            arguments: [account, groupRoom.id, 0, 0, #"["달빛"]"#]
        )
    }
    try queue.close()
}

/// The schema the shipped build writes today: every per-room setting exists
/// except how often the room is judged.
private func seedPolicyAtKeywordSchema(at url: URL) throws {
    let queue = try DatabaseQueue(path: url.path)
    try TalkFlowDatabase.migrator.migrate(queue, upTo: "v6-room-response-keywords")
    try queue.write { db in
        try db.execute(
            sql: """
            INSERT INTO room_policies
                (account_fingerprint, chat_id, response_mode, spontaneous_level,
                 delivery_mode, minimum_interval, prefers_recent_human_reply,
                 tags_recipient_by_name, active_hours_limited,
                 active_hours_start_minute, active_hours_end_minute, reads_photos,
                 response_keywords)
            VALUES (?, ?, 'automatic', 'low', 'always', 900, 1, 1, 0, ?, ?, 1, ?)
            """,
            arguments: [account, groupRoom.id, 0, 0, #"["달빛"]"#]
        )
    }
    try queue.close()
}

/// Leaves the file the way an older build would have left it: migrated as far as
/// v3, one room configured, and the connection shut before anything else opens
/// it.
private func seedPolicyAtOlderSchema(at url: URL) throws {
    let queue = try DatabaseQueue(path: url.path)
    try TalkFlowDatabase.migrator.migrate(queue, upTo: "v3-trigger-message-text")
    try queue.write { db in
        try db.execute(
            sql: """
            INSERT INTO room_policies
                (account_fingerprint, chat_id, response_mode, spontaneous_level,
                 delivery_mode, minimum_interval, prefers_recent_human_reply)
            VALUES (?, ?, 'automatic', 'medium', 'always', 0, 1)
            """,
            arguments: [account, groupRoom.id]
        )
    }
    try queue.close()
}

/// The schema the shipped build writes today: tagging and answering hours exist,
/// photos do not. The row uses every one of those columns so the upgrade has
/// something to lose.
private func seedPolicyAtTaggingSchema(at url: URL) throws {
    let queue = try DatabaseQueue(path: url.path)
    try TalkFlowDatabase.migrator.migrate(queue, upTo: "v4-room-tagging-and-active-hours")
    try queue.write { db in
        try db.execute(
            sql: """
            INSERT INTO room_policies
                (account_fingerprint, chat_id, response_mode, spontaneous_level,
                 delivery_mode, minimum_interval, prefers_recent_human_reply,
                 tags_recipient_by_name, active_hours_limited,
                 active_hours_start_minute, active_hours_end_minute)
            VALUES (?, ?, 'automatic', 'medium', 'always', 0, 0, 1, 1, ?, ?)
            """,
            arguments: [account, groupRoom.id, 9 * 60, 23 * 60]
        )
    }
    try queue.close()
}

/// The schema the shipped build writes today: every per-room setting exists
/// except the room's own keywords. The row sets all of them, so the upgrade has
/// something to lose in each column.
private func seedPolicyAtPhotoSchema(at url: URL) throws {
    let queue = try DatabaseQueue(path: url.path)
    try TalkFlowDatabase.migrator.migrate(queue, upTo: "v5-room-photo-context")
    try queue.write { db in
        try db.execute(
            sql: """
            INSERT INTO room_policies
                (account_fingerprint, chat_id, response_mode, spontaneous_level,
                 delivery_mode, minimum_interval, prefers_recent_human_reply,
                 tags_recipient_by_name, active_hours_limited,
                 active_hours_start_minute, active_hours_end_minute, reads_photos)
            VALUES (?, ?, 'mentionOnly', 'medium', 'always', 900, 0, 1, 1, ?, ?, 1)
            """,
            arguments: [account, groupRoom.id, 9 * 60, 23 * 60]
        )
    }
    try queue.close()
}

@Test
func policiesAreScopedToTheAccountThatConfiguredThem() async throws {
    let (database, cleanup) = try makeDatabase()
    defer { cleanup() }
    let repository = RoomPolicyRepository(database: database)

    var policy = try await repository.policy(for: groupRoom, accountFingerprint: account)
    policy.responseMode = .automatic
    try await repository.save(policy)

    let otherAccount = try await repository.policy(for: groupRoom, accountFingerprint: "katok-other")
    let mine = try await repository.policies(accountFingerprint: account)

    #expect(otherAccount.responseMode == .off)
    #expect(mine[groupRoom.id]?.responseMode == .automatic)
    #expect(try await repository.policies(accountFingerprint: "katok-other").isEmpty)
}

@Test
func savingAPolicyTwiceUpdatesItInsteadOfFailing() async throws {
    let (database, cleanup) = try makeDatabase()
    defer { cleanup() }
    let repository = RoomPolicyRepository(database: database)

    var policy = try await repository.policy(for: groupRoom, accountFingerprint: account)
    policy.responseMode = .mentionOnly
    try await repository.save(policy)
    policy.responseMode = .off
    try await repository.save(policy)

    #expect(try await repository.policy(for: groupRoom, accountFingerprint: account).responseMode == .off)
}

@Test
func theGlobalPauseAndLaunchSwitchesDoNotOverwriteEachOther() async throws {
    let (database, cleanup) = try makeDatabase()
    defer { cleanup() }
    let repository = AppSettingsRepository(database: database)

    #expect(try await repository.globalResponsesEnabled() == false)
    #expect(try await repository.launchesAtLogin() == false)

    try await repository.setGlobalResponsesEnabled(true)
    try await repository.setLaunchesAtLogin(true)
    try await repository.setGlobalResponsesEnabled(false)

    #expect(try await repository.globalResponsesEnabled() == false)
    #expect(try await repository.launchesAtLogin() == true)
}

/// The model choice shares `app_settings` with the switches and writes only its
/// own column. A writer that rewrote the whole row would undo whichever switch
/// was flipped in between, and both live on the 설정 screen.
@Test
func theModelChoiceAndTheSwitchesDoNotOverwriteEachOther() async throws {
    let (database, cleanup) = try makeDatabase()
    defer { cleanup() }
    let repository = AppSettingsRepository(database: database)

    #expect(try await repository.aiModel() == .codexDefault)

    try await repository.setAIModel(.pinned(.named("gpt-5.6-terra")))
    try await repository.setGlobalResponsesEnabled(true)
    try await repository.setWakesDisplayToSend(false)

    #expect(try await repository.aiModel() == .pinned(.named("gpt-5.6-terra")))
    #expect(try await repository.globalResponsesEnabled())
    #expect(try await repository.wakesDisplayToSend() == false)

    try await repository.setAIModel(.codexDefault)

    #expect(try await repository.aiModel() == .codexDefault)
    #expect(try await repository.globalResponsesEnabled())
}

@Test
func responseStyleRoundTripsIncludingEveryKeyword() async throws {
    let (database, cleanup) = try makeDatabase()
    defer { cleanup() }
    let repository = AppSettingsRepository(database: database)

    let style = ResponseStyle(
        tone: "정중하고 짧게",
        length: .long,
        emojiUse: .frequent,
        assertiveness: .forward,
        responseKeywords: ["한결", "hangyeol", "달구봇"]
    )
    try await repository.save(style)

    #expect(try await repository.responseStyle() == style)
}

/// The keywords predate the rename and are still stored in `mention_tokens`.
/// A row written by the older build has to keep reading back as it was.
@Test
func keywordsWrittenBeforeTheRenameStillLoad() async throws {
    let (database, cleanup) = try makeDatabase()
    defer { cleanup() }

    try await database.queue.write { db in
        try db.execute(
            sql: """
            INSERT INTO response_style_settings
                (id, tone, length, emoji_use, assertiveness, mention_tokens)
            VALUES (1, ?, ?, ?, ?, ?)
            """,
            arguments: ["친근하고 간결하게", "short", "sparing", "reserved", #"["달구봇"]"#]
        )
    }

    let style = try await AppSettingsRepository(database: database).responseStyle()

    #expect(style.responseKeywords == ["달구봇"])
}

@Test
func responseStyleFallsBackToDefaultsBeforeItIsEverSaved() async throws {
    let (database, cleanup) = try makeDatabase()
    defer { cleanup() }

    let style = try await AppSettingsRepository(database: database).responseStyle()

    #expect(style == ResponseStyle())
    #expect(style.responseKeywords.isEmpty)
}

@Test
func rememberedRoomNamesTrackKakaoTalkWithoutBecomingPolicyKeys() async throws {
    let (database, cleanup) = try makeDatabase()
    defer { cleanup() }
    let repository = RoomPolicyRepository(database: database)

    try await repository.rememberRooms([groupRoom], accountFingerprint: account)
    try await repository.rememberRooms(
        [ChatRoom(id: groupRoom.id, displayName: "이름 바뀐 방", kind: .group)],
        accountFingerprint: account
    )

    var policy = try await repository.policy(for: groupRoom, accountFingerprint: account)
    policy.responseMode = .mentionOnly
    try await repository.save(policy)

    let renamed = ChatRoom(id: groupRoom.id, displayName: "또 바뀐 이름", kind: .group)
    #expect(try await repository.policy(for: renamed, accountFingerprint: account).responseMode == .mentionOnly)
}

// MARK: - 먼저 말 걸기

/// The migration that matters most of all of them. Speaking unasked is the first
/// thing this app does that nobody requested, so a room somebody configured
/// before the setting existed comes back with it off — including a room already
/// set to send its replies without asking. That agreement was about answering.
@Test
func aRoomConfiguredBeforeOpenersExistedComesBackSilentEvenIfItAlreadyAutoSends() async throws {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "talkflow-migration-\(UUID().uuidString)/talkflow.sqlite")
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    try seedPolicyAtAnsweredRunSchema(at: url)

    let policy = try await RoomPolicyRepository(database: try TalkFlowDatabase(fileURL: url))
        .policy(for: groupRoom, accountFingerprint: account)

    #expect(policy.conversationOpener == .off)
    #expect(policy.openerDeliversAutomatically == false)
    // And nothing the user did set is lost on the way through.
    #expect(policy.deliveryMode == .always)
    #expect(policy.responseMode == .automatic)
    #expect(policy.interjectionChance == .always)
    #expect(policy.judgementInterval == JudgementInterval(shortest: 60, longest: 600))
    #expect(policy.activeHours == ReplyActiveHours(isLimited: true, startMinute: 9 * 60, endMinute: 23 * 60))
    #expect(policy.readsPhotos)
    #expect(policy.responseKeywords == ["달빛"])
}

/// A room that was already there gets a cadence without anybody typing one, so
/// switching the setting on is one choice rather than two.
@Test
func aMigratedRoomAlreadyHoldsTheSuggestedOpenerCadence() async throws {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "talkflow-migration-\(UUID().uuidString)/talkflow.sqlite")
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    try seedPolicyAtAnsweredRunSchema(at: url)

    let policy = try await RoomPolicyRepository(database: try TalkFlowDatabase(fileURL: url))
        .policy(for: groupRoom, accountFingerprint: account)

    #expect(policy.conversationOpenerInterval == JudgementIntervalInput.conversationOpener.time.suggested)
}

@Test
func theOpenerAndItsRangeRoundTripThroughTheStore() async throws {
    let (database, cleanup) = try makeDatabase()
    defer { cleanup() }
    let repository = RoomPolicyRepository(database: database)

    guard case let .success(typed) = JudgementIntervalInput.conversationOpener.interval(
        shortest: "45",
        longest: "240",
        unit: .minutes
    ) else {
        Issue.record("45분~240분은 받아들여야 합니다")
        return
    }

    var policy = try await repository.policy(for: groupRoom, accountFingerprint: account)
    policy.responseMode = .automatic
    policy.conversationOpener = .delivers
    policy.conversationOpenerInterval = typed
    try await repository.save(policy)

    let reloaded = try await repository.policy(for: groupRoom, accountFingerprint: account)

    #expect(reloaded == policy)
    #expect(reloaded.conversationOpenerInterval == JudgementInterval(shortest: 2700, longest: 14400))
}

/// The question the ten-second sweep asks before it does anything expensive.
@Test
func theStoreAnswersWhetherAnyRoomOpensConversationsAtAll() async throws {
    let (database, cleanup) = try makeDatabase()
    defer { cleanup() }
    let repository = RoomPolicyRepository(database: database)

    var policy = try await repository.policy(for: groupRoom, accountFingerprint: account)
    policy.responseMode = .automatic
    try await repository.save(policy)
    #expect(try await repository.anyRoomOpensConversations() == false)

    policy.conversationOpener = .draftOnly
    try await repository.save(policy)
    #expect(try await repository.anyRoomOpensConversations())

    policy.conversationOpener = .off
    try await repository.save(policy)
    #expect(try await repository.anyRoomOpensConversations() == false)
}

/// The schema the shipped build writes today: every per-room setting exists
/// except whether the room may speak first. The row sets all of them, so the
/// upgrade has something to lose in each column.
private func seedPolicyAtAnsweredRunSchema(at url: URL) throws {
    let queue = try DatabaseQueue(path: url.path)
    try TalkFlowDatabase.migrator.migrate(queue, upTo: "v10-action-answered-run")
    try queue.write { db in
        try db.execute(
            sql: """
            INSERT INTO room_policies
                (account_fingerprint, chat_id, response_mode, spontaneous_level,
                 delivery_mode, minimum_interval, judgement_interval,
                 judgement_interval_longest, prefers_recent_human_reply,
                 tags_recipient_by_name, active_hours_limited,
                 active_hours_start_minute, active_hours_end_minute, reads_photos,
                 response_keywords)
            VALUES (?, ?, 'automatic', 'medium', 'always', 900, 60, 600, 1, 1, 1, ?, ?, 1, ?)
            """,
            arguments: [account, groupRoom.id, 9 * 60, 23 * 60, #"["달빛"]"#]
        )
    }
    try queue.close()
}

/// The upgrade that put the room in a note's key, tested the way it happens: the
/// old schema, filled in, then migrated.
///
/// A table rebuild is the one migration shape that can lose somebody's writing,
/// and what these notes are is paragraphs about real people that a model cannot
/// reconstruct. The room is recovered from the action log, so the log is seeded
/// first and the note second — the order the shipped file is in.
@Test
func theRoomIsRecoveredForEveryNoteThatHadOneBeforeItWasKeyedByRoom() async throws {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "talkflow-migrate-\(UUID().uuidString)/talkflow.sqlite")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )

    let queue = try DatabaseQueue(path: url.path)
    try TalkFlowDatabase.migrator.migrate(queue, upTo: "v23-person-link-relation")
    try await queue.write { db in
        for (chatID, senderID) in [("room-studio", "s-kang"), ("room-family", "s-jisu")] {
            try db.execute(
                sql: """
                INSERT INTO agent_actions
                    (account_fingerprint, chat_id, kind, trigger_sender_id, detail, created_at)
                VALUES (?, ?, 'reply', ?, '', ?)
                """,
                arguments: [account, chatID, senderID, Date(timeIntervalSince1970: 1_000)]
            )
            try db.execute(
                sql: """
                INSERT INTO person_notes
                    (sender_id, display_name, note, is_user_edited,
                     covered_through_message_id, updated_at)
                VALUES (?, ?, ?, 1, 'm-42', ?)
                """,
                arguments: [senderID, "이름-\(senderID)", "\(chatID)에서 적은 메모", Date(timeIntervalSince1970: 2_000)]
            )
            try db.execute(
                sql: """
                INSERT INTO person_links (sender_id, position, label, url, relation)
                VALUES (?, 0, '블로그', ?, 'made')
                """,
                arguments: [senderID, "https://example.com/\(senderID)"]
            )
        }
        // A note whose person has no reply on record. There is no room to put it
        // in, and inventing one would file somebody's paragraph under a room they
        // were never answered in.
        try db.execute(
            sql: """
            INSERT INTO person_notes
                (sender_id, display_name, note, is_user_edited,
                 covered_through_message_id, updated_at)
            VALUES ('s-orphan', '연결 없는 사람', '방을 찾을 수 없는 메모', 0, NULL, ?)
            """,
            arguments: [Date(timeIntervalSince1970: 2_000)]
        )
    }
    try queue.close()

    let database = try TalkFlowDatabase(fileURL: url)
    let notes = PersonNoteRepository(database: database)

    let inStudio = try await #require(notes.note(inRoom: "room-studio", senderID: "s-kang"))
    #expect(inStudio.chatRoomID == "room-studio")
    #expect(inStudio.note == "room-studio에서 적은 메모")
    // Everything the old row carried survives the rebuild, the hand-edited flag
    // and the refresh cursor included — losing either would have the next sweep
    // overwrite somebody's own writing and re-read the whole history to do it.
    #expect(inStudio.isPinned)
    #expect(inStudio.coveredThroughMessageID == "m-42")
    #expect(inStudio.links.map(\.url) == ["https://example.com/s-kang"])
    #expect(inStudio.links.first?.relation == .made)

    let inFamily = try await #require(notes.note(inRoom: "room-family", senderID: "s-jisu"))
    #expect(inFamily.note == "room-family에서 적은 메모")

    // And the note is only in its own room, which is the whole point of the key.
    #expect(try await notes.note(inRoom: "room-family", senderID: "s-kang") == nil)
    #expect(try await notes.note(inRoom: "room-studio", senderID: "s-jisu") == nil)

    let orphaned = try await database.queue.read { db in
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM person_notes WHERE sender_id = 's-orphan'")
    }
    #expect(orphaned == 0)
}

/// 고정이 디스크를 왕복하는지. 저장하고 다시 읽었을 때 풀려 있으면 갱신이
/// 고정된 메모를 덮어쓴다 — `savePeople`은 읽어 온 값의 `isPinned`만 보고
/// 건너뛸지 정하므로, 읽기에서 false가 되면 그 방어가 통째로 사라진다.
@Test
func aPinnedNoteComesBackPinned() async throws {
    let (database, cleanup) = try makeDatabase()
    defer { cleanup() }
    let notes = PersonNoteRepository(database: database)

    try await notes.save(
        PersonNote(
            chatRoomID: groupRoom.id,
            senderID: "s-kang",
            displayName: "강민석",
            note: "지켜야 하는 문장",
            links: [PersonLink(label: "블로그", url: "https://example.com", relation: .made)],
            isPinned: true,
            coveredThroughMessageID: "m-42",
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
    )

    let read = try await #require(notes.note(inRoom: groupRoom.id, senderID: "s-kang"))
    #expect(read.isPinned)
    #expect(read.note == "지켜야 하는 문장")
    #expect(read.coveredThroughMessageID == "m-42")

    // And through the list the 사람 tab uses, which is a different query with its
    // own row mapping. It lists only people this account has replied to, so the
    // action log has to say so before the note appears at all.
    try await database.queue.write { db in
        try db.execute(
            sql: """
            INSERT INTO agent_actions
                (account_fingerprint, chat_id, kind, trigger_sender_id, detail, created_at)
            VALUES (?, ?, 'reply', 's-kang', '', ?)
            """,
            arguments: [account, groupRoom.id, Date(timeIntervalSince1970: 1_000)]
        )
    }

    let listed = try await notes.notes(inRoom: groupRoom.id, accountFingerprint: account)
    #expect(listed.first?.isPinned == true)
}
