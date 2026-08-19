import Foundation
import GRDB
import TalkFlowDomain

public struct PendingSendRepository: PendingSendStore {
    private let database: TalkFlowDatabase

    public init(database: TalkFlowDatabase) {
        self.database = database
    }

    public func enqueue(_ send: PendingSend) async throws {
        try await database.queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO pending_sends
                    (account_fingerprint, chat_id, trigger_message_id, trigger_sender_id,
                     opens_conversation_after_message_id, text,
                     eligible_at, state, detail, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    send.accountFingerprint,
                    send.chatRoomID,
                    send.triggerMessageID,
                    send.triggerSenderID,
                    send.opensConversationAfterMessageID,
                    send.text,
                    send.eligibleAt,
                    send.state.rawValue,
                    send.detail,
                    send.createdAt
                ]
            )
        }
    }

    public func waiting() async throws -> [PendingSend] {
        try await fetch(
            sql: Self.selectSQL + " WHERE s.state = 'waiting' ORDER BY s.eligible_at ASC",
            arguments: []
        )
    }

    public func recent(limit: Int) async throws -> [PendingSend] {
        try await fetch(
            sql: Self.selectSQL + " ORDER BY s.created_at DESC, s.id DESC LIMIT ?",
            arguments: [limit]
        )
    }

    public func resolve(id: Int64, state: PendingSend.State, detail: String) async throws {
        try await database.queue.write { db in
            try db.execute(
                sql: "UPDATE pending_sends SET state = ?, detail = ? WHERE id = ?",
                arguments: [state.rawValue, detail, id]
            )
        }
    }

    private func fetch(sql: String, arguments: StatementArguments) async throws -> [PendingSend] {
        try await database.queue.read { db in
            try Row.fetchAll(db, sql: sql, arguments: arguments).compactMap(PendingSend.init(row:))
        }
    }

    private static let selectSQL = """
    SELECT s.*, COALESCE(r.display_name, '') AS display_name
    FROM pending_sends s
    LEFT JOIN chat_rooms r
        ON r.chat_id = s.chat_id AND r.account_fingerprint = s.account_fingerprint
    """
}

private extension PendingSend {
    init?(row: Row) {
        guard let id = row["id"] as Int64?,
              let fingerprint = row["account_fingerprint"] as String?,
              let chatID = row["chat_id"] as String?,
              let triggerMessageID = row["trigger_message_id"] as String?,
              let text = row["text"] as String?,
              let eligibleAt = row["eligible_at"] as Date?,
              let state = (row["state"] as String?).flatMap(State.init(rawValue:)),
              let createdAt = row["created_at"] as Date?
        else {
            return nil
        }

        self.init(
            id: id,
            accountFingerprint: fingerprint,
            chatRoomID: chatID,
            chatRoomName: row["display_name"] as String? ?? "",
            triggerMessageID: triggerMessageID,
            triggerSenderID: row["trigger_sender_id"] as String?,
            opensConversationAfterMessageID: row["opens_conversation_after_message_id"] as String?,
            text: text,
            eligibleAt: eligibleAt,
            state: state,
            detail: row["detail"] as String? ?? "",
            createdAt: createdAt
        )
    }
}
