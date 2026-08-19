/// How an answer is written: tone, length, emoji, how forward it is.
///
/// Registered once in 설정 and used by every room that has not written its own.
/// A room that has is holding one of these too — see
/// `RoomPolicy.responseStyleOverride` — so there is one shape of style rather
/// than a global one and a per-room one that can drift apart.
///
/// The keywords are the exception and stay global whatever a room does. They are
/// not style: they decide which messages count as a call, which the room's own
/// list already covers separately.
public struct ResponseStyle: Equatable, Sendable {
    public enum Length: String, CaseIterable, Equatable, Sendable {
        case short
        case medium
        case long

        public var title: String {
            switch self {
            case .short: "짧게"
            case .medium: "보통"
            case .long: "길게"
            }
        }
    }

    public enum EmojiUse: String, CaseIterable, Equatable, Sendable {
        case none
        case sparing
        case frequent

        public var title: String {
            switch self {
            case .none: "쓰지 않음"
            case .sparing: "가끔"
            case .frequent: "자주"
            }
        }
    }

    public enum Assertiveness: String, CaseIterable, Equatable, Sendable {
        case reserved
        case balanced
        case forward

        public var title: String {
            switch self {
            case .reserved: "신중하게"
            case .balanced: "보통"
            case .forward: "적극적으로"
            }
        }
    }

    public var tone: String
    public var length: Length
    public var emojiUse: EmojiUse
    public var assertiveness: Assertiveness
    /// Extra words that count as a call, on top of the account's own KakaoTalk
    /// name. The name is detected rather than registered, so this list is for
    /// what the name does not cover: a bot alias, an old nickname people still
    /// use, an initial. Several can be registered, and matching ignores case.
    public var responseKeywords: [String]

    public init(
        tone: String = "친근하고 간결하게",
        length: Length = .short,
        emojiUse: EmojiUse = .sparing,
        assertiveness: Assertiveness = .reserved,
        responseKeywords: [String] = []
    ) {
        self.tone = tone
        self.length = length
        self.emojiUse = emojiUse
        self.assertiveness = assertiveness
        self.responseKeywords = responseKeywords
    }
}
