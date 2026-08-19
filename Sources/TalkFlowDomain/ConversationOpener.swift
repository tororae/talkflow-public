import Foundation

/// Whether TalkFlow may start a conversation in this room, and how far that is
/// allowed to go.
///
/// Everything else this app does is a response: something arrived and the rules
/// decided whether to answer it. This is the one setting that puts words into a
/// room under the user's name with nobody having asked, which is exactly when a
/// message is most likely to land wrong. So it is off in every room, it stays off
/// until somebody switches it on for one specific room, and every gate that
/// already guards replies guards this first.
///
/// Delivery is a second choice rather than a consequence of the first. A room set
/// to 상시 전송 said TalkFlow may answer for the user; it did not say TalkFlow may
/// speak for them, and reading the one as the other is how a feature nobody
/// enabled starts talking.
public enum ConversationOpener: String, CaseIterable, Equatable, Sendable {
    case off
    /// Writes the opener and waits for a person, whatever the room's 전송 방식 is.
    case draftOnly
    /// Lets the opener go out the way the room's replies do. Never more permissive
    /// than 전송 방식: a room on 초안만 still only drafts.
    case delivers

    public var title: String {
        switch self {
        case .off: "꺼짐"
        case .draftOnly: "초안만"
        case .delivers: "전송까지"
        }
    }

    public var isOn: Bool { self != .off }
}

/// What a *repeat* opener talks about — the ones sent because TalkFlow spoke last
/// and nobody has answered since (see `openerRepeatLimit`).
///
/// The first opener always comes out of the room's own recent conversation; this
/// only decides the ones after it. Carrying the subject on reads as pressing the
/// same point; a fresh one reads as trying a different way in. Neither is right
/// for every room, so it is the room's to pick.
public enum OpenerRepeatTopic: String, CaseIterable, Equatable, Sendable {
    /// Stay on the subject the last opener raised.
    case carryOn
    /// Drop it and open something new.
    case fresh

    public var title: String {
        switch self {
        case .carryOn: "이어가기"
        case .fresh: "새 주제"
        }
    }
}

/// A key that ties an opener's draft to whatever later resolves it.
///
/// The record's `triggerMessageID` is that key everywhere else, and it names the
/// message being answered — which an opener does not have. It gets an id of its
/// own instead of borrowing the room's newest message, because two rows sharing
/// a trigger id are one row as far as "has this draft been dealt with?" is
/// concerned, and a pending reply would be marked handled by an opener going out.
public enum ConversationOpenerKey {
    public static let prefix = "opener:"

    public static func make() -> String {
        prefix + UUID().uuidString
    }
}
