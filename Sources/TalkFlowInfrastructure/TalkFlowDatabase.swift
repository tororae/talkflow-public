import Foundation
import GRDB
import TalkFlowDomain

/// TalkFlow's own store: policies, settings, and activity.
///
/// Kept separate from katok's archive on purpose. The archive is a rebuildable
/// copy of KakaoTalk; this file holds decisions the user made and cannot be
/// recovered by syncing again.
public struct TalkFlowDatabase: Sendable {
    let queue: DatabaseQueue

    public init(fileURL: URL? = nil) throws {
        let url = try fileURL ?? Self.defaultFileURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        queue = try DatabaseQueue(path: url.path)
        try Self.migrator.migrate(queue)
    }

    public static func defaultFileURL() throws -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/TalkFlow/talkflow.sqlite")
    }

    /// Reachable inside the module so an upgrade can be tested the way it
    /// happens: an older schema, filled in, then migrated.
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        Self.registerMigrationsV1toV10(in: &migrator)
        Self.registerMigrationsV11toV17(in: &migrator)
        Self.registerMigrationsV18toV22(in: &migrator)
        Self.registerMigrationsV23toV31(in: &migrator)

        return migrator
    }
}
