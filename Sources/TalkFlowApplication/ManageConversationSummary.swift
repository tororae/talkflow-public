import Foundation
import TalkFlowDomain

public enum ConversationSummaryError: LocalizedError, Equatable {
    case accountNotVerified(reason: String)
    case tooLong
    case refreshFailed
    case pinned

    public var errorDescription: String? {
        switch self {
        case let .accountNotVerified(reason): reason
        case .tooLong: "\(ConversationSummary.characterLimit)자까지 적을 수 있습니다."
        case .refreshFailed: "요약을 갱신하지 못했습니다. 잠시 뒤 다시 시도하세요."
        // Said rather than done silently. A button that appears to work and
        // changes nothing is worse than one that explains itself.
        case .pinned: "고정해 둔 요약이라 갱신하지 않았습니다. 고정을 풀고 다시 누르세요."
        }
    }
}

/// What the room screen can do to a room's standing note: read it, correct it,
/// refresh it now, throw it away.
///
/// All four exist because the note is a claim about the user's friends. One they
/// cannot see is one they never agreed to, one they cannot correct is the app
/// insisting on its own reading, and one they cannot delete is a file about
/// somebody that outlives the reason it was written.
public struct ManageConversationSummary: Sendable {
    private let connection: any KakaoConnection
    private let summaryStore: any ConversationSummaryStore
    private let refresher: ConversationSummaryRefresher

    public init(
        connection: any KakaoConnection,
        summaryStore: any ConversationSummaryStore,
        writer: any ConversationSummaryWriter,
        personNotes: (any PersonNoteStore)? = nil,
        policyStore: (any RoomPolicyStore)? = nil,
        actionLog: (any AgentActionLog)? = nil
    ) {
        self.connection = connection
        self.summaryStore = summaryStore
        refresher = ConversationSummaryRefresher(
            connection: connection,
            summaryStore: summaryStore,
            writer: writer,
            personNotes: personNotes,
            policyStore: policyStore,
            actionLog: actionLog
        )
    }

    public func summary(for room: ChatRoom) async throws -> ConversationSummary? {
        try await summaryStore.summary(for: room, accountFingerprint: try await fingerprint())
    }

    /// The user's own words, kept as typed. Not pinned — writing a sentence is not
    /// a decision to stop the note ever being refreshed, and 고정 is the checkbox
    /// beside the field.
    ///
    /// Refuses an overlong text rather than shortening it: a field that rewrites
    /// itself while somebody is typing is what made the keyword box unusable, and
    /// this one is edited a paragraph at a time.
    @discardableResult
    public func saveEdit(_ text: String, for room: ChatRoom) async throws -> ConversationSummary {
        guard !ConversationSummary.exceedsLimit(text) else { throw ConversationSummaryError.tooLong }
        let account = try await fingerprint()
        let existing = try? await summaryStore.summary(for: room, accountFingerprint: account)

        // A room with no note yet can still be given one by hand. That is the
        // case the whole feature is for — "前 직장 동료, 존댓말 유지" is not
        // derivable from any amount of conversation, and it should not have to
        // wait for a model call to become sayable.
        let edited = existing?.edited(text, at: Date()) ?? ConversationSummary(
            accountFingerprint: account,
            chatRoomID: room.id,
            text: text,
            updatedAt: Date()
        )
        try await summaryStore.save(edited)
        return edited
    }

    /// 고정, written on its own so the switch does not have to travel through the
    /// text field. A room with no note yet has nothing to pin.
    @discardableResult
    public func setPinned(_ pinned: Bool, for room: ChatRoom) async throws -> ConversationSummary {
        let account = try await fingerprint()
        guard let existing = try? await summaryStore.summary(for: room, accountFingerprint: account) else {
            throw ConversationSummaryError.refreshFailed
        }
        let updated = ConversationSummary(
            accountFingerprint: existing.accountFingerprint,
            chatRoomID: existing.chatRoomID,
            text: existing.text,
            updatedAt: existing.updatedAt,
            isPinned: pinned,
            coveredThroughMessageID: existing.coveredThroughMessageID,
            coveredMessageCount: existing.coveredMessageCount
        )
        try await summaryStore.save(updated)
        return updated
    }

    /// The button, and it stops at 고정 just as the sweep does.
    ///
    /// It used to refresh a hand-edited note on the grounds that the user had
    /// asked. That reasoning held only while the flag was set by typing: once the
    /// pin is a switch somebody deliberately threw, honouring it here is the point
    /// of the switch. A pinned note reports the refresh as refused rather than
    /// silently doing nothing, so the screen can say why.
    public func refreshNow(for room: ChatRoom) async throws -> ConversationSummary {
        let account = try await fingerprint()
        let previous = try? await summaryStore.summary(for: room, accountFingerprint: account)
        if let previous, previous.isPinned { throw ConversationSummaryError.pinned }
        guard let refreshed = await refresher.refresh(
            room: room,
            accountFingerprint: account,
            previous: previous,
            now: Date()
        ) else {
            throw ConversationSummaryError.refreshFailed
        }
        return refreshed
    }

    public func clear(for room: ChatRoom) async throws {
        try await summaryStore.clear(chatRoomID: room.id, accountFingerprint: try await fingerprint())
    }

    /// Resolved here rather than passed in, for the reason every other screen-side
    /// use case resolves it here: a note written under one account's fingerprint
    /// and read under another's would be one account's description of people shown
    /// beside a different account's rooms.
    private func fingerprint() async throws -> String {
        switch await connection.status() {
        case let .connected(profile):
            return profile.fingerprint
        case let .unavailable(reason):
            throw ConversationSummaryError.accountNotVerified(reason: reason)
        case .disconnected:
            throw ConversationSummaryError.accountNotVerified(reason: "카카오톡에 연결되어 있지 않습니다.")
        }
    }
}
