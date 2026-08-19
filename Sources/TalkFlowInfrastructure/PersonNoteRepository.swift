import Foundation
import GRDB
import TalkFlowDomain

public struct PersonNoteRepository: PersonNoteStore {
    private let database: TalkFlowDatabase

    public init(database: TalkFlowDatabase) {
        self.database = database
    }

    public func note(inRoom chatRoomID: String, senderID: String) async throws -> PersonNote? {
        try await database.queue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM person_notes WHERE chat_id = ? AND sender_id = ?",
                arguments: [chatRoomID, senderID]
            ) else {
                return nil
            }
            return Self.note(
                row,
                links: try Self.links(db, chatRoomID: chatRoomID, senderID: senderID)
            )
        }
    }

    /// The people in one room, which is what the 사람 tab lists.
    ///
    /// The room is now on the note itself, so this no longer asks the action log
    /// *who* is in the room. It still asks whether this account is the one that
    /// replied to them: a room id belongs to KakaoTalk and not to an account, so
    /// two accounts in the same room would otherwise read each other's notes.
    public func notes(
        inRoom chatRoomID: String,
        accountFingerprint: String
    ) async throws -> [PersonNote] {
        try await database.queue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT n.* FROM person_notes n
                WHERE n.chat_id = ?
                  AND EXISTS (
                    SELECT 1 FROM agent_actions a
                    WHERE a.chat_id = n.chat_id
                      AND a.trigger_sender_id = n.sender_id
                      AND a.account_fingerprint = ?
                  )
                ORDER BY n.updated_at DESC
                """,
                arguments: [chatRoomID, accountFingerprint]
            )
            return try rows.map { row in
                Self.note(
                    row,
                    links: try Self.links(
                        db,
                        chatRoomID: row["chat_id"],
                        senderID: row["sender_id"]
                    )
                )
            }
        }
    }

    /// Written whole, links and all, in one transaction.
    ///
    /// The links are deleted and rewritten rather than reconciled. There are at
    /// most five of them, and a reconciliation that gets an ordering wrong is a
    /// worse bug than the write it saves.
    public func save(_ note: PersonNote) async throws {
        try await database.queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO person_notes
                    (chat_id, sender_id, display_name, note, is_pinned,
                     covered_through_message_id, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(chat_id, sender_id) DO UPDATE SET
                    display_name = excluded.display_name,
                    note = excluded.note,
                    is_pinned = excluded.is_pinned,
                    covered_through_message_id = excluded.covered_through_message_id,
                    updated_at = excluded.updated_at
                """,
                arguments: [
                    note.chatRoomID,
                    note.senderID,
                    note.displayName,
                    note.note,
                    note.isPinned,
                    note.coveredThroughMessageID,
                    note.updatedAt
                ]
            )
            try db.execute(
                sql: "DELETE FROM person_links WHERE chat_id = ? AND sender_id = ?",
                arguments: [note.chatRoomID, note.senderID]
            )
            for (position, link) in note.links.enumerated() {
                try db.execute(
                    sql: """
                    INSERT INTO person_links
                        (chat_id, sender_id, position, label, url, relation, last_mentioned_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        note.chatRoomID,
                        note.senderID,
                        position,
                        link.label,
                        link.url,
                        link.relation.rawValue,
                        link.lastMentionedAt
                    ]
                )
            }
        }
    }

    /// Takes the links with it. A note the user deleted is a person they asked
    /// TalkFlow to forget, and leaving their addresses behind is not forgetting.
    ///
    /// Forgetting them here does not forget them elsewhere: the same person in
    /// another room is another note, which is the point of the room being in the
    /// key. The editor says so on screen rather than leaving it to be discovered.
    public func delete(inRoom chatRoomID: String, senderID: String) async throws {
        try await database.queue.write { db in
            try db.execute(
                sql: "DELETE FROM person_links WHERE chat_id = ? AND sender_id = ?",
                arguments: [chatRoomID, senderID]
            )
            try db.execute(
                sql: "DELETE FROM person_notes WHERE chat_id = ? AND sender_id = ?",
                arguments: [chatRoomID, senderID]
            )
        }
    }

    private static func links(
        _ db: Database,
        chatRoomID: String,
        senderID: String
    ) throws -> [PersonLink] {
        try Row.fetchAll(
            db,
            sql: """
            SELECT label, url, relation, last_mentioned_at FROM person_links
            WHERE chat_id = ? AND sender_id = ? ORDER BY position
            """,
            arguments: [chatRoomID, senderID]
        )
        .map {
            PersonLink(
                label: $0["label"],
                url: $0["url"],
                // An unreadable value is not a claim about whose work this is.
                relation: ($0["relation"] as String?)
                    .flatMap(PersonLink.Relation.init(rawValue:)) ?? .unknown,
                lastMentionedAt: $0["last_mentioned_at"]
            )
        }
    }

    private static func note(_ row: Row, links: [PersonLink]) -> PersonNote {
        PersonNote(
            chatRoomID: row["chat_id"],
            senderID: row["sender_id"],
            displayName: row["display_name"],
            note: row["note"],
            links: links,
            isPinned: row["is_pinned"] as Bool? ?? false,
            coveredThroughMessageID: row["covered_through_message_id"],
            updatedAt: row["updated_at"] as Date? ?? Date(timeIntervalSince1970: 0)
        )
    }
}
