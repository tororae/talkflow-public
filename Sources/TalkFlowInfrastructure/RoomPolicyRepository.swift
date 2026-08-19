import Foundation
import GRDB
import TalkFlowDomain

public struct RoomPolicyRepository: RoomPolicyStore {
    private let database: TalkFlowDatabase

    public init(database: TalkFlowDatabase) {
        self.database = database
    }

    public func policy(for room: ChatRoom, accountFingerprint: String) async throws -> RoomPolicy {
        // Rows are mapped inside the closure because GRDB's `Row` is not Sendable:
        // returning one would force the blocking overload onto an async caller.
        let stored = try await database.queue.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT * FROM room_policies WHERE account_fingerprint = ? AND chat_id = ?",
                arguments: [accountFingerprint, room.id]
            )
            .flatMap(Self.policy(inRow:))
        }

        return stored ?? .makeDefault(accountFingerprint: accountFingerprint, room: room)
    }

    public func policies(accountFingerprint: String) async throws -> [String: RoomPolicy] {
        let stored = try await database.queue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM room_policies WHERE account_fingerprint = ?",
                arguments: [accountFingerprint]
            )
            .compactMap(Self.policy(inRow:))
        }

        return stored.reduce(into: [:]) { result, policy in
            result[policy.chatRoomID] = policy
        }
    }

    /// One row, decoded by `RoomPolicyRow`'s coding keys and then mapped.
    ///
    /// Fetched as a `Row` and decoded here rather than fetched as
    /// `RoomPolicyRow` directly, so that a row this build cannot read is one
    /// missing policy instead of a failed load: the bulk read draws every room on
    /// screen, and one bad row throwing would take the other rooms' settings with
    /// it. That room shows its default, and `save` refuses to write over it.
    ///
    /// The reader this replaced did not return nil for such a row — it crashed.
    /// `Row`'s subscripts decode with `try!`, so text in `minimum_interval` was
    /// `GRDB/Row.swift:509: Fatal error: 'try!' expression unexpectedly raised an
    /// error: could not decode Optional<Double>` and signal 5. Nil was only ever
    /// for a missing key or a `response_mode`/`delivery_mode` word the enum did
    /// not know. So this is a crash traded for a room that draws as off and
    /// cannot be saved over, which is the trade only because of that refusal:
    /// without it the same row would have been silently overwritable.
    private static func policy(inRow row: Row) -> RoomPolicy? {
        (try? RoomPolicyRow(row: row)).flatMap(RoomPolicy.init(row:))
    }

    /// One upsert over every column the row has.
    ///
    /// GRDB writes `INSERT INTO room_policies (…48 columns…) VALUES (…) ON
    /// CONFLICT DO UPDATE SET <the 46 that are not the primary key> =
    /// excluded.<column> RETURNING rowid`, which is the statement this used to
    /// spell out by hand. Traced with `Database.trace` against the old SQL: the
    /// same 48 columns in the same order, the same 46 assignments in the same
    /// order. Two textual differences, neither of them behaviour:
    ///
    /// - No conflict target. Any uniqueness violation triggers the update rather
    ///   than the primary key's alone, and `PRAGMA index_list` on this table
    ///   returns one index — `sqlite_autoindex_room_policies_1` on
    ///   `(account_fingerprint, chat_id)`, the primary key — so there is nothing
    ///   else for it to catch.
    /// - `RETURNING rowid`, which is how GRDB feeds its own `didInsert`. It is
    ///   still one `INSERT … ON CONFLICT DO UPDATE`: the row is updated in place,
    ///   never deleted and reinserted, so rowids do not move.
    ///
    /// The read in front of it is a guard against overwriting settings nobody can
    /// see. A row this build cannot decode reads as `makeDefault` for display, and
    /// a default is a whole policy — so one `저장` in the room screen, or one `!켬`
    /// typed into the console, used to replace all 46 non-key columns with
    /// defaults and take 답변 조건, 참고 지시 and 키워드 with them, unrecoverably and
    /// with nothing said. `RoomPolicySaveRefusal` is thrown instead.
    ///
    /// One indexed read per save, which is free where it happens: every save is a
    /// person pressing a button or typing a command, never the reply path.
    ///
    /// Inside the same transaction as the upsert, so no other writer can slip a
    /// row in between the check and the write. Only a *decodable* row may be
    /// replaced; a room with no row at all has nothing to protect and is inserted.
    ///
    /// The guard asks `RoomPolicyRow` and stops there, so it catches a value of
    /// the wrong storage class and not a `response_mode` or `delivery_mode` word
    /// this build does not recognise: that row decodes, `RoomPolicy.init(row:)`
    /// then refuses it, it reads as the default, and saving over it still loses
    /// the other 45 columns. Left as it is because that gap is older than this
    /// guard and closing it has a cost of its own — a build that stopped knowing
    /// a mode, a downgrade, would leave the room unsaveable with no way out from
    /// inside the app.
    public func save(_ policy: RoomPolicy) async throws {
        let row = RoomPolicyRow(policy: policy)
        try await database.queue.write { db in
            let existing = try Row.fetchOne(
                db,
                sql: "SELECT * FROM room_policies WHERE account_fingerprint = ? AND chat_id = ?",
                arguments: [row.accountFingerprint, row.chatRoomID]
            )
            if let existing, (try? RoomPolicyRow(row: existing)) == nil {
                throw RoomPolicySaveRefusal(chatRoomID: row.chatRoomID)
            }
            try row.upsert(db)
        }
    }

    /// One `EXISTS` in front of a process launch and a read of every room. The
    /// sweep that asks this runs every few seconds and the honest answer is no
    /// for anybody who never went looking for the setting.
    public func anyRoomOpensConversations() async throws -> Bool {
        try await database.queue.read { db in
            try Bool.fetchOne(
                db,
                sql: """
                SELECT EXISTS(
                    SELECT 1 FROM room_policies WHERE conversation_opener <> ?
                )
                """,
                arguments: [ConversationOpener.off.rawValue]
            ) ?? false
        }
    }

    /// Keeps the display names TalkFlow shows in step with KakaoTalk without ever
    /// letting a name become the key a policy hangs on.
    public func hiddenRoomIDs(accountFingerprint: String) async throws -> Set<String> {
        try await database.queue.read { db in
            Set(try String.fetchAll(
                db,
                sql: "SELECT chat_id FROM chat_rooms WHERE account_fingerprint = ? AND hidden_at IS NOT NULL",
                arguments: [accountFingerprint]
            ))
        }
    }

    /// Written onto the room row rather than the policy, because hiding is about
    /// the list rather than about how the room behaves — and the settings have to
    /// survive it. Unhiding gives the room back exactly as it was configured.
    public func setRoomHidden(
        _ hidden: Bool,
        chatRoomID: String,
        accountFingerprint: String
    ) async throws {
        let hiddenAt: Date? = hidden ? Date() : nil
        try await database.queue.write { db in
            try db.execute(
                sql: "UPDATE chat_rooms SET hidden_at = ? WHERE account_fingerprint = ? AND chat_id = ?",
                arguments: [hiddenAt, accountFingerprint, chatRoomID]
            )
        }
    }

    public func rememberRooms(_ rooms: [ChatRoom], accountFingerprint: String) async throws {
        try await database.queue.write { db in
            for room in rooms {
                try db.execute(
                    sql: """
                    INSERT INTO chat_rooms (account_fingerprint, chat_id, display_name, kind)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(account_fingerprint, chat_id) DO UPDATE SET
                        display_name = excluded.display_name,
                        kind = excluded.kind
                    """,
                    arguments: [accountFingerprint, room.id, room.displayName, room.kind.rawValue]
                )
            }
        }
    }
}
