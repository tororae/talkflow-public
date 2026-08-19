import Foundation
import GRDB
import TalkFlowDomain

/// Read-only access to the archive katok maintains.
///
/// katok is the only writer. Opening read-only makes that guarantee explicit and
/// keeps a TalkFlow bug from corrupting an archive that took a full sync to build.
/// The schema coupling stops with this reader and the row mapping beside it;
/// callers see domain models.
struct KatokArchiveReader: Sendable {
    enum ReadError: LocalizedError {
        case archiveMissing

        var errorDescription: String? {
            "카카오톡 대화 아카이브가 아직 없습니다. 동기화를 먼저 실행하세요."
        }
    }

    private let database: DatabaseQueue
    private let accountSenderID: String?
    /// katok stores every account it has ever synced in one archive, so reads
    /// have to be scoped. Without this a room list mixes accounts, and a reply
    /// could be drafted from a conversation the signed-in account never had.
    private let accountHash: String?

    init(environment: KatokEnvironment = KatokEnvironment()) throws {
        let url = environment.archiveURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ReadError.archiveMissing
        }

        var configuration = Configuration()
        configuration.readonly = true
        database = try DatabaseQueue(path: url.path, configuration: configuration)
        accountSenderID = environment.accountIdentity()?.senderID
        accountHash = Self.accountHash(in: database, senderID: accountSenderID)
    }

    /// katok's own account key is not derivable from anything TalkFlow holds, so
    /// it is looked up: the account whose messages this user sent. Falling back
    /// to the most recently active account keeps a brand-new account, where the
    /// user has not written yet, from reading as every account at once.
    private static func accountHash(in database: DatabaseQueue, senderID: String?) -> String? {
        try? database.read { db in
            if let senderID,
               let owned = try String.fetchOne(
                   db,
                   sql: "SELECT account_hash FROM messages WHERE sender_id = ? LIMIT 1",
                   arguments: [senderID]
               ) {
                return owned
            }
            return try String.fetchOne(
                db,
                sql: "SELECT account_hash FROM messages ORDER BY timestamp DESC LIMIT 1"
            )
        }
    }

    /// The name KakaoTalk shows for this account: the nickname stamped on the
    /// messages it sent. Nothing else in the archive names the account.
    ///
    /// The newest one wins, because renaming yourself leaves every older message
    /// under the old name. Nil is a real answer — an account that has never
    /// written has no name on record — and borrowing somebody else's would have
    /// the app answer to a stranger.
    func accountNickname() -> String? {
        newestNickname(inChat: nil)
    }

    /// The name this account goes by in one room.
    ///
    /// The nickname is stamped on each message rather than held once per account,
    /// and KakaoTalk lets the same account carry a different name in each chat —
    /// open chats are where people do it on purpose. Read across all rooms, a
    /// room where the user renamed themselves never hears its own name called.
    ///
    /// Falling back to the all-rooms answer covers the room this account has not
    /// written in yet: there is no name to read there, and the name it uses
    /// everywhere else is the one that room would know it by.
    func accountNickname(chatRoomID: String) -> String? {
        newestNickname(inChat: chatRoomID) ?? accountNickname()
    }

    /// The newest name this account wrote under, in one room or in any of them.
    ///
    /// A blank nickname is no nickname: katok writes one for some rows, and an
    /// empty name would match every message ever sent.
    private func newestNickname(inChat chatRoomID: String?) -> String? {
        guard let accountSenderID else { return nil }
        let accountHash = accountHash

        let stored = try? database.read { db -> String? in
            guard let chatRoomID else {
                return try String.fetchOne(
                    db,
                    sql: """
                    SELECT sender_nickname
                    FROM messages
                    WHERE account_hash = ? AND sender_id = ?
                    ORDER BY timestamp DESC
                    LIMIT 1
                    """,
                    arguments: [accountHash, accountSenderID]
                )
            }
            // Scoping to a room stays an indexed read: (chat_id, timestamp,
            // message_id) covers the filter and the ordering both, so the room's
            // newest row is found without walking its history.
            return try String.fetchOne(
                db,
                sql: """
                SELECT sender_nickname
                FROM messages
                WHERE account_hash = ? AND sender_id = ? AND chat_id = ?
                ORDER BY timestamp DESC
                LIMIT 1
                """,
                arguments: [accountHash, accountSenderID, chatRoomID]
            )
        }

        return stored
            .flatMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    func chatRooms() throws -> [ChatRoom] {
        // Rooms come from `messages` rather than `chats` because only `messages`
        // records which account a room belongs to.
        let accountHash = accountHash
        return try database.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT DISTINCT chat_id, chat_name, chat_type
                FROM messages
                WHERE account_hash = ?
                """,
                arguments: [accountHash]
            )
            .compactMap(ChatRoom.init(archiveRow:))
        }
    }

    func recentMessages(chatRoomID: String, limit: Int) throws -> [ChatMessage] {
        let senderID = accountSenderID
        let accountHash = accountHash
        return try database.read { db in
            let parser = ISO8601DateFormatter()
            parser.formatOptions = [.withInternetDateTime]

            // The (chat_id, timestamp, message_id) index covers this ordering, so
            // the newest slice is read without scanning the chat's full history.
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT message_id, chat_id, sender_id, sender_nickname, text, timestamp,
                       message_type, reply_to_message_id
                FROM messages
                WHERE chat_id = ? AND account_hash = ?
                ORDER BY timestamp DESC, message_id DESC
                LIMIT ?
                """,
                arguments: [chatRoomID, accountHash, limit]
            )

            return rows
                .compactMap { ChatMessage(archiveRow: $0, accountSenderID: senderID, parser: parser) }
                .reversed()
        }
    }

    /// The newest message the archive holds. Compared against KakaoTalk's own
    /// database to notice when the two have drifted apart.
    func newestMessageDate() throws -> Date? {
        let accountHash = accountHash
        return try database.read { db in
            let parser = ISO8601DateFormatter()
            parser.formatOptions = [.withInternetDateTime]
            return try String.fetchOne(
                db,
                sql: "SELECT MAX(timestamp) FROM messages WHERE account_hash = ?",
                arguments: [accountHash]
            )
            .flatMap(parser.date(from:))
        }
    }

    /// Message and chat totals for the connection status screen.
    func archiveSummary() throws -> (messages: Int, chatRooms: Int) {
        try database.read { db in
            let messages = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM messages") ?? 0
            let chatRooms = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM chats") ?? 0
            return (messages, chatRooms)
        }
    }
}
