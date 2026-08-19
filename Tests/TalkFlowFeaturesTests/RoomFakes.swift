import Foundation
import TalkFlowDomain

/// Remembers what the rooms screen saved, so a test can read the store back
/// instead of trusting the model's own copy of what it thinks it wrote.
///
/// A locked class rather than an actor because a test seeds it before the model
/// exists, where nothing can be awaited.
final class FakeRoomPolicyStore: RoomPolicyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String: RoomPolicy] = [:]

    func preload(_ policy: RoomPolicy) {
        lock.withLock { stored[policy.chatRoomID] = policy }
    }

    func saved(_ chatRoomID: String) -> RoomPolicy? {
        lock.withLock { stored[chatRoomID] }
    }

    func policy(for room: ChatRoom, accountFingerprint: String) async throws -> RoomPolicy {
        saved(room.id) ?? .makeDefault(accountFingerprint: accountFingerprint, room: room)
    }

    func policies(accountFingerprint: String) async throws -> [String: RoomPolicy] {
        lock.withLock { stored }
    }

    /// Makes every save refuse, the way `RoomPolicyRepository` refuses to write
    /// over a stored row it cannot decode. The store keeps what it already had,
    /// because a refused save is a save that did not happen.
    func refuseSaves(with error: any Error) {
        lock.withLock { saveRefusal = error }
    }

    private var saveRefusal: (any Error)?

    func save(_ policy: RoomPolicy) async throws {
        if let refusal = lock.withLock({ saveRefusal }) { throw refusal }
        preload(policy)
    }

    func rememberRooms(_ rooms: [ChatRoom], accountFingerprint: String) async throws {}

    private var hiddenRooms: Set<String> = []

    func hiddenRoomIDs(accountFingerprint: String) async throws -> Set<String> {
        lock.withLock { hiddenRooms }
    }

    func setRoomHidden(_ hidden: Bool, chatRoomID: String, accountFingerprint: String) async throws {
        lock.withLock {
            if hidden { hiddenRooms.insert(chatRoomID) } else { hiddenRooms.remove(chatRoomID) }
        }
    }

    func anyRoomOpensConversations() async throws -> Bool {
        lock.withLock { stored.values.contains { $0.conversationOpener.isOn } }
    }
}

/// Only the one question the rooms screen asks of the log: when this room was
/// last put to the model, which is where its current cycle started.
struct FakeJudgementLog: AgentActionLog {
    var lastJudgement: Date?

    func lastJudgementDate(chatRoomID: String, accountFingerprint: String) async throws -> Date? {
        lastJudgement
    }

    func record(_ action: AgentAction) async throws {}
    func recent(limit: Int) async throws -> [AgentAction] { [] }
    func recent(chatRoomID: String, limit: Int) async throws -> [AgentAction] { [] }
    func lastReplyDate(chatRoomID: String, accountFingerprint: String) async throws -> Date? { nil }
    func hasAction(chatRoomID: String, triggerMessageID: String) async throws -> Bool { false }
    func openerCount(chatRoomID: String, accountFingerprint: String, since: Date) async throws -> Int { 0 }
    func pendingDrafts(limit: Int) async throws -> [AgentAction] { [] }
    func dismissDraft(id: Int64) async throws {}

    func replyCountsBySender(
        chatRoomID: String,
        accountFingerprint: String
    ) async throws -> [(senderID: String, displayName: String, count: Int)] { [] }

}
