import Foundation
import GRDB
import TalkFlowDomain

public struct ConversationSummaryRepository: ConversationSummaryStore {
    private let database: TalkFlowDatabase

    public init(database: TalkFlowDatabase) {
        self.database = database
    }

    public func summary(
        for room: ChatRoom,
        accountFingerprint: String
    ) async throws -> ConversationSummary? {
        // Rows are mapped inside the closure because GRDB's `Row` is not Sendable:
        // returning one would force the blocking overload onto an async caller.
        try await database.queue.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT * FROM room_summaries WHERE account_fingerprint = ? AND chat_id = ?",
                arguments: [accountFingerprint, room.id]
            )
            .flatMap(ConversationSummary.init(row:))
        }
    }

    public func summaries(accountFingerprint: String) async throws -> [String: ConversationSummary] {
        let stored = try await database.queue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM room_summaries WHERE account_fingerprint = ?",
                arguments: [accountFingerprint]
            )
            .compactMap(ConversationSummary.init(row:))
        }

        return stored.reduce(into: [:]) { result, summary in
            result[summary.chatRoomID] = summary
        }
    }

    public func save(_ summary: ConversationSummary) async throws {
        try await database.queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO room_summaries
                    (account_fingerprint, chat_id, summary_text, updated_at,
                     is_pinned, covered_through_message_id, covered_message_count)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(account_fingerprint, chat_id) DO UPDATE SET
                    summary_text = excluded.summary_text,
                    updated_at = excluded.updated_at,
                    is_pinned = excluded.is_pinned,
                    covered_through_message_id = excluded.covered_through_message_id,
                    covered_message_count = excluded.covered_message_count
                """,
                arguments: [
                    summary.accountFingerprint,
                    summary.chatRoomID,
                    summary.text,
                    summary.updatedAt,
                    summary.isPinned,
                    summary.coveredThroughMessageID,
                    summary.coveredMessageCount
                ]
            )
        }
    }

    /// A delete, not a blanking. The screen offers this because the row is a
    /// description of people the user knows, and the only honest reading of
    /// "지우기" is that nothing is left.
    public func clear(chatRoomID: String, accountFingerprint: String) async throws {
        try await database.queue.write { db in
            try db.execute(
                sql: "DELETE FROM room_summaries WHERE account_fingerprint = ? AND chat_id = ?",
                arguments: [accountFingerprint, chatRoomID]
            )
        }
    }
}

private extension ConversationSummary {
    init?(row: Row) {
        guard let fingerprint = row["account_fingerprint"] as String?,
              let chatID = row["chat_id"] as String?,
              let text = row["summary_text"] as String?,
              let updatedAt = row["updated_at"] as Date?
        else {
            return nil
        }

        self.init(
            accountFingerprint: fingerprint,
            chatRoomID: chatID,
            text: text,
            updatedAt: updatedAt,
            // A row whose flag will not read is treated as the model's, so the
            // sweep is free to refresh it. The other way round would freeze a note
            // nobody ever edited, and the room screen would say a person wrote it.
            isPinned: row["is_pinned"] as Bool? ?? false,
            coveredThroughMessageID: row["covered_through_message_id"] as String?,
            coveredMessageCount: row["covered_message_count"] as Int? ?? 0
        )
    }
}
