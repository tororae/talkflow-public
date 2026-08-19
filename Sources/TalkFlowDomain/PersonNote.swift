import Foundation

/// What TalkFlow has written down about one person **in one room**.
///
/// Keyed on the room and the sender id KakaoTalk stamps on every message, never
/// on the name. Names are display: 졸린 하마, Mina and 공지알림봇 are each two
/// different people in this account's rooms, and keyed on the name each pair
/// would share one file from the first day.
/// (닉네임은 지어낸 것이다. 실제로 그런 방이 있었다는 것만 사실이다.)
///
/// The room is half the key because somebody in one room is not the same
/// correspondent as the same human in another — a different register, a different
/// running topic, and nothing learned in one place should surface in the other.
/// KakaoTalk agrees more than it looks: it stamps a *different* sender id on the
/// same person in every group room, so 왕만두 already arrives as five ids across
/// five rooms. Only two ids in this account span rooms at all — this account
/// itself and the user's own — and both are cases where merging is wrong too.
///
/// This replaced a key of `sender_id` alone, which had been argued for with two
/// numbers read off the logged-out account (`PLATFORM-FINDINGS` §1.4).
public struct PersonNote: Equatable, Sendable {
    /// Which room this note is about the person in. Half the key.
    public let chatRoomID: String
    public let senderID: String
    /// The name to draw in a list, kept only so the user can find the person.
    /// Never the key, and never load-bearing.
    public var displayName: String
    public var note: String
    public var links: [PersonLink]
    /// Set when a person edits the note by hand, and it stops the refresh from
    /// overwriting them — the same bargain 채팅방 요약 makes. What somebody wrote
    /// about their own friend outranks what a model inferred from thirty lines.
    /// Whether the refresh is allowed to rewrite this note. A checkbox in the note
    /// editor, and the only thing that stops a rewrite.
    ///
    /// It used to be inferred from having typed, and for a person note that was a
    /// one-way door: `savePeople` skipped anybody whose note was hand-edited and
    /// nothing in the app ever cleared the flag, so fixing a single name meant
    /// never learning another fact about that person. Editing and pinning are
    /// separate now — a correction is a correction, and stopping the refresh is
    /// something the user asks for.
    public var isPinned: Bool
    /// Where the last refresh got to, so the next one reads what came after
    /// instead of the whole history again.
    public var coveredThroughMessageID: String?
    public var updatedAt: Date

    public init(
        chatRoomID: String,
        senderID: String,
        displayName: String,
        note: String,
        links: [PersonLink] = [],
        isPinned: Bool = false,
        coveredThroughMessageID: String? = nil,
        updatedAt: Date
    ) {
        self.chatRoomID = chatRoomID
        self.senderID = senderID
        self.displayName = displayName
        self.note = String(ConversationFence.neutralised(note).prefix(Self.characterLimit))
        self.links = links
        self.isPinned = isPinned
        self.coveredThroughMessageID = coveredThroughMessageID
        self.updatedAt = updatedAt
    }

    /// Half of what a room gets, and for a reason rather than by halving.
    ///
    /// A room summary describes a whole conversation and is allowed 600; a person
    /// is narrower. The number that matters is what this costs on the reply call,
    /// where the conversation itself has a 4,000 character budget: at 300 a note
    /// is under a tenth of it. Measured against the room summaries one measured
    /// account actually has — 312 to 573 characters against a 600 ceiling — a
    /// model fills whatever it is given, so the ceiling is the setting.
    public static let characterLimit = 300

    /// How many links ride along on a reply, not how many are kept.
    ///
    /// It used to be a storage cap and the sixth link was silently dropped, with
    /// nothing on screen to say which one lost. Nothing is gained by forgetting:
    /// the cost this number exists to bound is the reply prompt, so the bound
    /// belongs there. The 사람 tab shows everything.
    public static let linksPerReply = 5

    /// The most recently mentioned first, which is what a reply wants and what
    /// the tab should show. Anything never seen in conversation sorts last rather
    /// than first — an address nobody has brought up in months is the one to push
    /// off the end of a prompt.
    public var linksForReply: [PersonLink] {
        links
            .sorted { ($0.lastMentionedAt ?? .distantPast) > ($1.lastMentionedAt ?? .distantPast) }
            .prefix(Self.linksPerReply)
            .map { $0 }
    }

    /// How many times somebody has to have been answered before a note is kept
    /// about them.
    ///
    /// Three. Below that a note is written from almost nothing and reads like it,
    /// and on one measured account the threshold moves the population from 145
    /// people to 73 — the difference between a list somebody can read and one they
    /// cannot. The eleven rooms that account syncs hold 350 people, so a note for
    /// everyone present would be two and a half times the list, most of it about
    /// people who have never been answered.
    ///
    /// In the domain rather than beside the code that applies it, so the help card
    /// can read the number instead of repeating it. A card that types a limit by
    /// hand goes on saying the old one after the constant moves.
    public static let replyThreshold = 3

    public var isEmpty: Bool {
        note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && links.isEmpty
    }
}

/// One address this person is known by, kept out of the prose on purpose.
///
/// A URL is the one thing in a note a model will confidently rewrite — a
/// character changed, a plausible path invented — and a note that quietly
/// corrupts somebody's link is worse than one that never had it. Held apart, the
/// prompt can say these are exact and not to be paraphrased, and the user can fix
/// one without editing a sentence around it.
public struct PersonLink: Equatable, Sendable {
    /// Whether this is theirs or something they passed on.
    ///
    /// The distinction a reply gets wrong in the most embarrassing direction.
    /// 「형이 만든 그 앱」 about a link somebody merely forwarded credits them with
    /// a stranger's work; the reverse dismisses their own. Neither is recoverable
    /// by apologising afterwards.
    ///
    /// `unknown` is the default and the honest answer for most links. A model
    /// asked to choose between made and shared will choose, and a guess recorded
    /// as a fact is exactly what this field exists to stop.
    public enum Relation: String, CaseIterable, Equatable, Sendable {
        case made
        case shared
        case unknown

        public var title: String {
            switch self {
            case .made: "직접 만든 것"
            case .shared: "공유한 것"
            case .unknown: "모름"
            }
        }
    }

    /// What to call this, short enough to say in a sentence.
    ///
    /// Name first and, where the name alone does not say it, what kind of thing
    /// it is — 「메뉴바 달력 앱 GitHub」 rather than either half alone. It is
    /// not a description: the 300-character note is, and for the one or two links
    /// most people have, a description here would say the same thing twice.
    ///
    /// It has to carry more when somebody has seven links, because then the note
    /// cannot describe them all. That is the case the bound is sized for — long
    /// enough to identify a thing, short enough that a list of them stays a list.
    public var label: String
    public var url: String
    public var relation: Relation
    /// When this last came up in conversation, which is how the list orders
    /// itself. Nil for a link that has not been seen since it was written down.
    public var lastMentionedAt: Date?

    /// Forty characters. Wide enough for 「macOS 메뉴바 달력 앱 GitHub」, which is
    /// the shape of what the model writes unprompted and is about the longest thing
    /// worth saying; past that it stops naming and starts explaining, which the note
    /// already does. (원문 대신 같은 모양으로 옮겨 적었다.)
    public static let labelLimit = 40

    public init(
        label: String,
        url: String,
        relation: Relation = .unknown,
        lastMentionedAt: Date? = nil
    ) {
        self.label = String(label.prefix(Self.labelLimit))
        self.url = url
        self.relation = relation
        self.lastMentionedAt = lastMentionedAt
    }
}

/// Where notes are kept.
///
/// Every call names a room. There is no way to ask for "this person" without
/// saying where, because there is no such object.
public protocol PersonNoteStore: Sendable {
    func note(inRoom chatRoomID: String, senderID: String) async throws -> PersonNote?
    func notes(inRoom chatRoomID: String, accountFingerprint: String) async throws -> [PersonNote]
    func save(_ note: PersonNote) async throws
    func delete(inRoom chatRoomID: String, senderID: String) async throws
}
