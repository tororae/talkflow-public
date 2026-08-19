import Foundation
import GRDB
import TalkFlowDomain

/// The `admin_rooms` table behind `AdminRoomStore`.
///
/// A row exists only for a room the operator turned into a console; its absence
/// is the default and the common case. Writes are idempotent so designating a
/// room twice is not an error, and un-designating simply removes the row —
/// there is no state to keep about a room that is no longer a console.
public struct AdminRoomRepository: AdminRoomStore {
    private let database: TalkFlowDatabase

    public init(database: TalkFlowDatabase) {
        self.database = database
    }

    public func adminRoomIDs(accountFingerprint: String) async throws -> Set<String> {
        try await database.queue.read { db in
            Set(try String.fetchAll(
                db,
                sql: "SELECT chat_id FROM admin_rooms WHERE account_fingerprint = ?",
                arguments: [accountFingerprint]
            ))
        }
    }

    public func setAdminRoom(
        _ isAdmin: Bool,
        chatRoomID: String,
        accountFingerprint: String
    ) async throws {
        try await database.queue.write { db in
            if isAdmin {
                try db.execute(
                    sql: """
                    INSERT INTO admin_rooms (account_fingerprint, chat_id)
                    VALUES (?, ?)
                    ON CONFLICT(account_fingerprint, chat_id) DO NOTHING
                    """,
                    arguments: [accountFingerprint, chatRoomID]
                )
            } else {
                try db.execute(
                    sql: "DELETE FROM admin_rooms WHERE account_fingerprint = ? AND chat_id = ?",
                    arguments: [accountFingerprint, chatRoomID]
                )
            }
        }
    }
}
