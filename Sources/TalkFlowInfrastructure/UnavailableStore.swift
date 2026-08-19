import Foundation
import TalkFlowDomain

/// Stands in when TalkFlow's own database cannot be opened.
///
/// Every call fails loudly rather than returning defaults: silently accepting a
/// policy change that is never written would tell the user a room is configured
/// when nothing was saved.
public struct UnavailableStore: RoomPolicyStore, AppSettingsStore, AgentActionLog, ConversationSummaryStore {
    public init() {}

    public func summary(
        for room: ChatRoom,
        accountFingerprint: String
    ) async throws -> ConversationSummary? {
        throw StoreError.unavailable
    }

    public func summaries(accountFingerprint: String) async throws -> [String: ConversationSummary] {
        throw StoreError.unavailable
    }

    public func save(_ summary: ConversationSummary) async throws {
        throw StoreError.unavailable
    }

    public func clear(chatRoomID: String, accountFingerprint: String) async throws {
        throw StoreError.unavailable
    }

    public func policy(for room: ChatRoom, accountFingerprint: String) async throws -> RoomPolicy {
        throw StoreError.unavailable
    }

    public func policies(accountFingerprint: String) async throws -> [String: RoomPolicy] {
        throw StoreError.unavailable
    }

    public func save(_ policy: RoomPolicy) async throws {
        throw StoreError.unavailable
    }

    public func rememberRooms(_ rooms: [ChatRoom], accountFingerprint: String) async throws {
        throw StoreError.unavailable
    }

    public func hiddenRoomIDs(accountFingerprint: String) async throws -> Set<String> {
        throw StoreError.unavailable
    }

    public func setRoomHidden(_ hidden: Bool, chatRoomID: String, accountFingerprint: String) async throws {
        throw StoreError.unavailable
    }

    public func anyRoomOpensConversations() async throws -> Bool {
        throw StoreError.unavailable
    }

    public func responseStyle() async throws -> ResponseStyle {
        throw StoreError.unavailable
    }

    public func save(_ style: ResponseStyle) async throws {
        throw StoreError.unavailable
    }

    public func answeringCondition() async throws -> AnsweringCondition {
        throw StoreError.unavailable
    }

    public func save(_ condition: AnsweringCondition) async throws {
        throw StoreError.unavailable
    }

    public func globalResponsesEnabled() async throws -> Bool {
        throw StoreError.unavailable
    }

    public func setGlobalResponsesEnabled(_ enabled: Bool) async throws {
        throw StoreError.unavailable
    }

    public func launchesAtLogin() async throws -> Bool {
        throw StoreError.unavailable
    }

    public func setLaunchesAtLogin(_ enabled: Bool) async throws {
        throw StoreError.unavailable
    }

    public func sendUsePolicyAccepted() async throws -> Bool {
        throw StoreError.unavailable
    }

    public func setSendUsePolicyAccepted(_ accepted: Bool) async throws {
        throw StoreError.unavailable
    }

    public func wakesDisplayToSend() async throws -> Bool {
        throw StoreError.unavailable
    }

    public func setWakesDisplayToSend(_ enabled: Bool) async throws {
        throw StoreError.unavailable
    }

    public func aiModel() async throws -> AIModelChoice {
        throw StoreError.unavailable
    }

    public func setAIModel(_ choice: AIModelChoice) async throws {
        throw StoreError.unavailable
    }

    public func record(_ action: AgentAction) async throws {
        throw StoreError.unavailable
    }

    public func recent(limit: Int) async throws -> [AgentAction] {
        throw StoreError.unavailable
    }

    public func recent(chatRoomID: String, limit: Int) async throws -> [AgentAction] {
        throw StoreError.unavailable
    }

    public func lastReplyDate(chatRoomID: String, accountFingerprint: String) async throws -> Date? {
        throw StoreError.unavailable
    }

    public func lastJudgementDate(chatRoomID: String, accountFingerprint: String) async throws -> Date? {
        throw StoreError.unavailable
    }

    public func hasAction(chatRoomID: String, triggerMessageID: String) async throws -> Bool {
        throw StoreError.unavailable
    }

    public func openerCount(chatRoomID: String, accountFingerprint: String, since: Date) async throws -> Int {
        throw StoreError.unavailable
    }

    public func replyCountsBySender(
        chatRoomID: String,
        accountFingerprint: String
    ) async throws -> [(senderID: String, displayName: String, count: Int)] {
        throw StoreError.unavailable
    }

    public func pendingDrafts(limit: Int) async throws -> [AgentAction] {
        throw StoreError.unavailable
    }

    public func dismissDraft(id: Int64) async throws {
        throw StoreError.unavailable
    }
}

/// The send queue's counterpart. Kept separate so that a store failure can never
/// be mistaken for an empty queue, which would read as "nothing to send".
public struct UnavailableSendStore: PendingSendStore {
    public init() {}

    public func enqueue(_ send: PendingSend) async throws {
        throw StoreError.unavailable
    }

    public func waiting() async throws -> [PendingSend] {
        throw StoreError.unavailable
    }

    public func recent(limit: Int) async throws -> [PendingSend] {
        throw StoreError.unavailable
    }

    public func resolve(id: Int64, state: PendingSend.State, detail: String) async throws {
        throw StoreError.unavailable
    }
}

enum StoreError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "TalkFlow 설정 저장소를 열지 못했습니다. 디스크 권한과 저장 공간을 확인하세요."
    }
}
