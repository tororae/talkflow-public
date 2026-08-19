import Foundation
import GRDB
@testable import TalkFlowInfrastructure

/// Builds a throwaway katok data directory that mirrors the real archive schema.
///
/// Tests never touch the user's own archive: it holds real conversations, and a
/// fixture is the only way to assert on specific rows.
struct KatokArchiveFixture {
    /// One archived row. A struct rather than the tuple this used to be: at
    /// eight fields the type stopped fitting in the signature that took it.
    struct ArchivedMessage {
        let id: String
        let chatID: String
        let senderID: String
        let nickname: String
        let text: String
        let timestamp: String
        let type: String
        /// The message this row answers, as KakaoTalk records a 답장. Null on
        /// almost every row in the real archive.
        let replyTo: String?
    }

    let directoryURL: URL

    var environment: KatokEnvironment {
        KatokEnvironment(dataDirectoryURL: directoryURL)
    }

    init(accountSenderID: String = "1000") throws {
        directoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "talkflow-fixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directoryURL.appending(path: "kakao"),
            withIntermediateDirectories: true
        )

        let authCache = ["user_id": Int(accountSenderID) ?? 0, "uuid": 0] as [String: Any]
        try JSONSerialization
            .data(withJSONObject: authCache)
            .write(to: directoryURL.appending(path: "kakao/auth.json"))
    }

    func destroy() {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    func createArchive(
        chats: [(id: String, name: String, type: String)],
        messages: [ArchivedMessage]
    ) throws {
        let database = try DatabaseQueue(path: environment.archiveURL.path)
        try database.write { db in
            try db.execute(sql: """
            CREATE TABLE chats (
                chat_id TEXT PRIMARY KEY,
                chat_name TEXT NOT NULL,
                chat_type TEXT NOT NULL
            )
            """)
            try db.execute(sql: """
            CREATE TABLE messages (
                account_hash TEXT NOT NULL,
                chat_id TEXT NOT NULL,
                chat_name TEXT NOT NULL,
                chat_type TEXT NOT NULL,
                message_id TEXT NOT NULL,
                sender_id TEXT NOT NULL,
                sender_nickname TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                text TEXT NOT NULL,
                message_type TEXT NOT NULL,
                reply_to_message_id TEXT,
                PRIMARY KEY(account_hash, chat_id, message_id)
            )
            """)

            for chat in chats {
                try db.execute(
                    sql: "INSERT INTO chats VALUES (?, ?, ?)",
                    arguments: [chat.id, chat.name, chat.type]
                )
            }
            for message in messages {
                // Messages carry the room's type because that is where room
                // listings read it from; `chats` has no account column and so
                // cannot be used once an archive holds more than one account.
                let chatType = chats.first { $0.id == message.chatID }?.type ?? "direct"
                try db.execute(
                    sql: "INSERT INTO messages VALUES ('acct', ?, 'room', ?, ?, ?, ?, ?, ?, ?, ?)",
                    arguments: [
                        message.chatID,
                        chatType,
                        message.id,
                        message.senderID,
                        message.nickname,
                        message.timestamp,
                        message.text,
                        message.type,
                        message.replyTo
                    ]
                )
            }
        }
    }
}
