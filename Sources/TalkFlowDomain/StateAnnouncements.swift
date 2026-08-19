import Foundation

/// Which of the four transitions this room hears about, and on what terms.
///
/// An empty set is off, which is where every room starts. This is the app
/// speaking without being spoken to — the same thing 먼저 말 걸기 is — so it
/// carries the same two consents: the room says whether it wants any of these at
/// all, and separately whether one may go out without a person pressing send.
public struct StateAnnouncements: Equatable, Sendable {
    /// The transitions this room is told about. Empty means silence.
    public var transitions: Set<StateAnnouncement>
    /// How recently somebody must have spoken for an announcement to be worth
    /// making.
    ///
    /// The whole gate, and the reason this feature does not turn into a bot
    /// posting 「왔다」 into an empty room every morning. A line explaining that
    /// somebody has arrived or left is only worth anything while there is a
    /// conversation for it to land in; into a silent room it is a greeting from
    /// nowhere, which is the one thing 먼저 말 걸기 already refuses to write.
    public var withinRecentConversation: TimeInterval
    public var delivery: AnnouncementDelivery

    public init(
        transitions: Set<StateAnnouncement> = [],
        withinRecentConversation: TimeInterval = 600,
        delivery: AnnouncementDelivery = .draftOnly
    ) {
        self.transitions = transitions
        self.withinRecentConversation = withinRecentConversation
        self.delivery = delivery
    }

    public static let off = StateAnnouncements()

    public var isOn: Bool { !transitions.isEmpty }

    public func announces(_ transition: StateAnnouncement) -> Bool {
        transitions.contains(transition)
    }

    /// Whether the room was live enough, this recently, to be told anything.
    public func worthTelling(lastMessageAt: Date?, at now: Date) -> Bool {
        guard let lastMessageAt else { return false }
        return now.timeIntervalSince(lastMessageAt) <= withinRecentConversation
    }
}

/// Whether an announcement may leave without a person.
///
/// Two cases and not three, because off is the empty transition set. Never more
/// permissive than the room's 전송 방식 — a room on 초안만 still only drafts, for
/// the reason `ConversationOpener` gives: agreeing that TalkFlow may answer for
/// you is not agreeing that it may speak for you.
public enum AnnouncementDelivery: String, CaseIterable, Equatable, Sendable {
    case draftOnly
    case delivers

    public var title: String {
        switch self {
        case .draftOnly: "초안만"
        case .delivers: "전송까지"
        }
    }
}
