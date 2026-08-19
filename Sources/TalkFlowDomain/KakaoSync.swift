import Foundation

public struct KakaoSyncReport: Equatable, Sendable {
    public let totalMessages: Int
    public let insertedMessages: Int
    public let updatedMessages: Int
    public let changedChatRoomIDs: [String]
    /// When the database was seen to move, which is earlier than this report by
    /// however long the sync waited out its interval and then ran.
    ///
    /// Carried so the reply the sync causes can say where that time went. It is
    /// the largest fixed cost on the path and the one a person watching a chat
    /// window experiences as the app being slow to notice them.
    ///
    /// Optional because a source that cannot say has to be able to say nothing
    /// rather than name the wrong instant.
    public let detectedAt: Date?
    public let synchronizedAt: Date

    public init(
        totalMessages: Int,
        insertedMessages: Int,
        updatedMessages: Int,
        changedChatRoomIDs: [String],
        detectedAt: Date? = nil,
        synchronizedAt: Date = Date()
    ) {
        self.totalMessages = totalMessages
        self.insertedMessages = insertedMessages
        self.updatedMessages = updatedMessages
        self.changedChatRoomIDs = changedChatRoomIDs
        self.detectedAt = detectedAt
        self.synchronizedAt = synchronizedAt
    }

    public var hasNewMessages: Bool {
        insertedMessages > 0
    }
}

public enum KakaoSyncEvent: Equatable, Sendable {
    case synchronized(KakaoSyncReport)
    case failed(reason: String)
    /// Detection stopped answering, and nothing was learned about the archive.
    ///
    /// Distinct from `failed`, which is a sync that ran and said no. This one
    /// never got that far, so a quiet chat and a dead detector produce the same
    /// silence — and only this case tells them apart on screen.
    case stalled(reason: String)
}

/// Reports local KakaoTalk changes after they have been archived.
///
/// Deciding what to do about a new message is a policy question and lives above
/// this port; a source only says that the archive moved and which rooms moved.
public protocol KakaoSyncSource: Sendable {
    func events() async -> AsyncStream<KakaoSyncEvent>
}
