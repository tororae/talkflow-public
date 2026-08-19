import Foundation
import GRDB
import TalkFlowDomain

public struct AgentActionRepository: AgentActionLog {
    private let database: TalkFlowDatabase

    public init(database: TalkFlowDatabase) {
        self.database = database
    }

    public func record(_ action: AgentAction) async throws {
        try await database.queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO agent_actions
                    (account_fingerprint, chat_id, kind, trigger_message_id, trigger_sender_id,
                     trigger_text, trigger_sender_name, answered_run,
                     reply_mode, confidence, reply_text, detail, context_message_count,
                     timeline, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    action.accountFingerprint,
                    action.chatRoomID,
                    action.kind.rawValue,
                    action.triggerMessageID,
                    action.triggerSenderID,
                    action.triggerText,
                    action.triggerSenderName,
                    AnsweredRunColumn.encode(action.answeredRun),
                    action.replyMode?.rawValue,
                    action.confidence?.rawValue,
                    action.replyText,
                    action.detail,
                    action.contextMessageCount,
                    ActionTimelineColumn.encode(action.timeline),
                    action.createdAt
                ]
            )
        }
    }

    public func recent(limit: Int) async throws -> [AgentAction] {
        try await fetch(sql: Self.selectSQL + " ORDER BY a.created_at DESC, a.id DESC LIMIT ?", arguments: [limit])
    }

    public func recent(chatRoomID: String, limit: Int) async throws -> [AgentAction] {
        try await fetch(
            sql: Self.selectSQL + " WHERE a.chat_id = ? ORDER BY a.created_at DESC, a.id DESC LIMIT ?",
            arguments: [chatRoomID, limit]
        )
    }

    public func lastReplyDate(chatRoomID: String, accountFingerprint: String) async throws -> Date? {
        try await database.queue.read { db in
            try Date.fetchOne(
                db,
                sql: """
                SELECT MAX(created_at) FROM agent_actions
                WHERE chat_id = ? AND account_fingerprint = ? AND kind IN ('drafted', 'sent')
                """,
                arguments: [chatRoomID, accountFingerprint]
            )
        }
    }

    /// The context count is what marks a model call: it is written only where a
    /// request was built, and every row that never reached the provider — a
    /// cooldown, a send failure, a dismissal — leaves it at zero. Kinds cannot
    /// tell those apart, and a room that batches would pace itself off rows that
    /// cost nothing.
    public func lastJudgementDate(chatRoomID: String, accountFingerprint: String) async throws -> Date? {
        try await database.queue.read { db in
            try Date.fetchOne(
                db,
                sql: """
                SELECT MAX(created_at) FROM agent_actions
                WHERE chat_id = ? AND account_fingerprint = ? AND context_message_count > 0
                """,
                arguments: [chatRoomID, accountFingerprint]
            )
        }
    }

    public func hasAction(chatRoomID: String, triggerMessageID: String) async throws -> Bool {
        try await database.queue.read { db in
            try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM agent_actions WHERE chat_id = ? AND trigger_message_id = ?)",
                arguments: [chatRoomID, triggerMessageID]
            ) ?? false
        }
    }

    /// Counts `opened` rows alone, and only those after `since`. The caller passes
    /// the other side's last utterance, so the count is the run of openers nobody
    /// has answered — which is what the gate weighs against `openerRepeatLimit`. A
    /// reply from anyone else lands after `since` moves forward and is never in the
    /// window, so the run reads as reset. Strictly greater than, matching the gate:
    /// the message the count starts from is that message, not an opener after it.
    public func openerCount(chatRoomID: String, accountFingerprint: String, since: Date) async throws -> Int {
        try await database.queue.read { db in
            try Int.fetchOne(
                db,
                sql: """
                SELECT COUNT(*) FROM agent_actions
                WHERE chat_id = ? AND account_fingerprint = ? AND kind = 'opened' AND created_at > ?
                """,
                arguments: [chatRoomID, accountFingerprint, since]
            ) ?? 0
        }
    }

    /// Counted off `drafted` and `sent` rows, which are the ones where a person
    /// actually got an answer. Holds are not: a room declines hundreds of times a
    /// day, and counting those would make everybody eligible for a note within a
    /// week of being in the room.
    public func replyCountsBySender(
        chatRoomID: String,
        accountFingerprint: String
    ) async throws -> [(senderID: String, displayName: String, count: Int)] {
        try await database.queue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT trigger_sender_id AS sender_id,
                       trigger_sender_name AS display_name,
                       COUNT(*) AS n
                FROM agent_actions
                WHERE chat_id = ? AND account_fingerprint = ?
                  AND trigger_sender_id IS NOT NULL
                  AND kind IN ('drafted', 'sent')
                GROUP BY trigger_sender_id
                """,
                arguments: [chatRoomID, accountFingerprint]
            )
            .map {
                (
                    senderID: $0["sender_id"] as String,
                    displayName: ($0["display_name"] as String?) ?? "",
                    count: $0["n"] as Int
                )
            }
        }
    }

    /// A draft counts as pending until something later resolves the same trigger
    /// message — a delivery, or the user dismissing it. A recorded failure does
    /// not resolve it: the reasons a send fails are states of the screen that
    /// pass, so the draft has to stay in the list to be tried again.
    ///
    /// An opener is here too, and has to be: 초안만 is what it takes by default
    /// even in a room that delivers replies on its own, so this list is the only
    /// way most of them ever get sent. Its trigger id is one of its own rather
    /// than a message id, which is what keeps it from resolving — or being
    /// resolved by — a reply waiting on the room's last message.
    public func pendingDrafts(limit: Int) async throws -> [AgentAction] {
        try await fetch(
            sql: Self.selectSQL + """
             WHERE a.kind IN ('drafted', 'opened')
               AND a.reply_text IS NOT NULL
               AND NOT EXISTS (
                   SELECT 1 FROM agent_actions later
                   WHERE later.chat_id = a.chat_id
                     AND later.trigger_message_id = a.trigger_message_id
                     AND later.kind IN ('sent', 'dismissed')
               )
             ORDER BY a.created_at DESC, a.id DESC
             LIMIT ?
            """,
            arguments: [limit]
        )
    }

    public func dismissDraft(id: Int64) async throws {
        try await database.queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO agent_actions
                    (account_fingerprint, chat_id, kind, trigger_message_id, detail, created_at)
                SELECT account_fingerprint, chat_id, 'dismissed', trigger_message_id,
                       '사용자가 초안을 무시했습니다.', ?
                FROM agent_actions WHERE id = ?
                """,
                arguments: [Date(), id]
            )
        }
    }

    private func fetch(sql: String, arguments: StatementArguments) async throws -> [AgentAction] {
        try await database.queue.read { db in
            try Row.fetchAll(db, sql: sql, arguments: arguments).compactMap(AgentAction.init(row:))
        }
    }

    /// Names live in `chat_rooms` so the timeline can label a room that no longer
    /// appears in the archive, while the action itself still keys on the room id.
    private static let selectSQL = """
    SELECT a.*, COALESCE(r.display_name, '') AS display_name
    FROM agent_actions a
    LEFT JOIN chat_rooms r
        ON r.chat_id = a.chat_id AND r.account_fingerprint = a.account_fingerprint
    """
}

private extension AgentAction {
    init?(row: Row) {
        guard let id = row["id"] as Int64?,
              let fingerprint = row["account_fingerprint"] as String?,
              let chatID = row["chat_id"] as String?,
              let kind = (row["kind"] as String?).flatMap(Kind.init(rawValue:)),
              let createdAt = row["created_at"] as Date?
        else {
            return nil
        }

        self.init(
            id: id,
            accountFingerprint: fingerprint,
            chatRoomID: chatID,
            chatRoomName: row["display_name"] as String? ?? "",
            kind: kind,
            triggerMessageID: row["trigger_message_id"] as String?,
            triggerSenderID: row["trigger_sender_id"] as String?,
            triggerText: row["trigger_text"] as String?,
            triggerSenderName: row["trigger_sender_name"] as String?,
            answeredRun: AnsweredRunColumn.decode(row["answered_run"] as String?),
            replyMode: (row["reply_mode"] as String?).flatMap(ReplyTrigger.init(rawValue:)),
            confidence: (row["confidence"] as String?).flatMap(ReplyDraft.Confidence.init(rawValue:)),
            replyText: row["reply_text"] as String?,
            detail: row["detail"] as String? ?? "",
            contextMessageCount: row["context_message_count"] as Int? ?? 0,
            timeline: ActionTimelineColumn.decode(row["timeline"] as String?),
            createdAt: createdAt
        )
    }
}
