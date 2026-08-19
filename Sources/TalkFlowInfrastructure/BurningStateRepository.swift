import Foundation
import GRDB
import TalkFlowDomain

public struct BurningStateRepository: BurningStateStore {
    private let database: TalkFlowDatabase

    public init(database: TalkFlowDatabase) {
        self.database = database
    }

    public func state(
        for chatRoomID: String,
        accountFingerprint: String
    ) async throws -> BurningState? {
        // Mapped inside the closure because GRDB's `Row` is not Sendable.
        try await database.queue.read { db in
            try Row.fetchOne(
                db,
                sql: """
                SELECT started_at, ends_at, cooldown_until FROM room_burning_state
                WHERE account_fingerprint = ? AND chat_id = ?
                """,
                arguments: [accountFingerprint, chatRoomID]
            )
            .flatMap { row in
                guard let started = row["started_at"] as Date?,
                      let ends = row["ends_at"] as Date?,
                      let cooldown = row["cooldown_until"] as Date?
                else {
                    return nil
                }
                return BurningState(startedAt: started, endsAt: ends, cooldownUntil: cooldown)
            }
        }
    }

    /// A new burn replaces whatever was there, and takes `announced_at` with it.
    ///
    /// Left behind, the previous burn's announcement would read as this one's,
    /// and this burn would end without a word.
    public func save(
        _ state: BurningState,
        for chatRoomID: String,
        accountFingerprint: String
    ) async throws {
        try await database.queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO room_burning_state
                    (account_fingerprint, chat_id, started_at, ends_at, cooldown_until, announced_at)
                VALUES (?, ?, ?, ?, ?, NULL)
                ON CONFLICT(account_fingerprint, chat_id) DO UPDATE SET
                    started_at = excluded.started_at,
                    ends_at = excluded.ends_at,
                    cooldown_until = excluded.cooldown_until,
                    announced_at = NULL
                """,
                arguments: [
                    accountFingerprint,
                    chatRoomID,
                    state.startedAt,
                    state.endsAt,
                    state.cooldownUntil
                ]
            )
        }
    }

    /// Only ever an update. A room with no burn on record has no end to have
    /// spoken about, and inserting a row here would invent one with no deadlines
    /// in it.
    public func markAnnounced(
        at instant: Date,
        for chatRoomID: String,
        accountFingerprint: String
    ) async throws {
        try await database.queue.write { db in
            try db.execute(
                sql: """
                UPDATE room_burning_state SET announced_at = ?
                WHERE account_fingerprint = ? AND chat_id = ?
                """,
                arguments: [instant, accountFingerprint, chatRoomID]
            )
        }
    }

    public func hoursWereOpen(
        for chatRoomID: String,
        accountFingerprint: String
    ) async throws -> Bool? {
        try await database.queue.read { db in
            try Bool.fetchOne(
                db,
                sql: """
                SELECT was_open FROM room_hours_phase
                WHERE account_fingerprint = ? AND chat_id = ?
                """,
                arguments: [accountFingerprint, chatRoomID]
            )
        }
    }

    public func recordHoursOpen(
        _ isOpen: Bool,
        for chatRoomID: String,
        accountFingerprint: String
    ) async throws {
        try await database.queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO room_hours_phase (account_fingerprint, chat_id, was_open)
                VALUES (?, ?, ?)
                ON CONFLICT(account_fingerprint, chat_id) DO UPDATE SET
                    was_open = excluded.was_open
                """,
                arguments: [accountFingerprint, chatRoomID, isOpen]
            )
        }
    }

    public func announcedAt(
        for chatRoomID: String,
        accountFingerprint: String
    ) async throws -> Date? {
        try await database.queue.read { db in
            try Date.fetchOne(
                db,
                sql: """
                SELECT announced_at FROM room_burning_state
                WHERE account_fingerprint = ? AND chat_id = ?
                """,
                arguments: [accountFingerprint, chatRoomID]
            )
        }
    }
}
