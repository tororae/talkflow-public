import Foundation

/// A named bundle of room settings, applied in one `!프리셋` command.
///
/// The console can already set any field one at a time; a preset is for the moves
/// an operator makes as a unit — "open this room all the way up", "just the
/// permissions", "keep it low-key" — so they are one word rather than five. Like
/// `PolicyEditor`, it is pure and in the domain: a preset is a function of the
/// policy it is handed, touching no store.
///
/// Presets deliberately set only the scalar/enum/toggle fields, never the free-text
/// ones (말투·답변 조건): the same fence that keeps a console line from rewriting a
/// room's voice keeps a preset from doing it wholesale.
public enum RoomPreset {
    /// Every preset with its one-line summary, in the order `!프리셋` lists them.
    public static let all: [(name: String, summary: String)] = [
        ("풀", "응답 자동·전송 상시·권한 전부 켬"),
        ("권한", "사진·웹검색·링크·대화기억·사람기억 켬"),
        ("조용히", "응답 멘션·먼저말 끔"),
    ]

    /// Folds a named preset into the policy, or nil when the name is not one.
    public static func apply(_ name: String, to policy: RoomPolicy) -> RoomPolicy? {
        var p = policy
        switch canonical(name) {
        case "풀":
            p.responseMode = .automatic
            p.deliveryMode = .always
            grantPermissions(&p)
        case "권한":
            grantPermissions(&p)
        case "조용히":
            p.responseMode = .mentionOnly
            p.conversationOpener = .off
        default:
            return nil
        }
        return p
    }

    /// The one-line description a reply echoes, or nil for an unknown preset.
    public static func summary(_ name: String) -> String? {
        all.first { $0.name == canonical(name) }?.summary
    }

    /// The permission bundle 풀 and 권한 share: everything that widens what leaves
    /// the Mac or remembers people, all on at once.
    private static func grantPermissions(_ p: inout RoomPolicy) {
        p.readsPhotos = true
        p.webSearch = true
        p.readsLinks = true
        p.remembersConversation = true
        p.remembersPeople = true
    }

    /// The one name each preset answers to, folding a couple of aliases in so a
    /// slightly-off word (풀오토, 권한전부) still lands.
    private static func canonical(_ name: String) -> String {
        switch name {
        case "풀", "풀오토", "full": "풀"
        case "권한", "권한전부", "권한모두": "권한"
        case "조용히", "조용", "quiet": "조용히"
        default: name
        }
    }
}
