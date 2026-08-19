import Foundation

/// Everything that counts as this account being called, in one room.
///
/// Being addressed by your own name and reacting to a word you registered used
/// to be one list, and that made `멘션에만 응답` unusable: the room could only
/// answer once somebody had typed the account's KakaoTalk name into settings by
/// hand, spelled the way other people spell it. The name is something the app
/// can read. A keyword is the extra word the user adds on top — for every room,
/// or for one.
public struct CallSigns: Equatable, Sendable {
    /// Read from KakaoTalk rather than typed. Nil until the account has sent a
    /// message the name can be read from.
    public let nickname: String?
    /// Registered in 설정 and in force in every room.
    public let globalKeywords: [String]
    /// Registered on one room and in force only there.
    public let roomKeywords: [String]

    public init(
        nickname: String? = nil,
        globalKeywords: [String] = [],
        roomKeywords: [String] = []
    ) {
        self.nickname = nickname.map(Self.normalized).flatMap { $0.isEmpty ? nil : $0 }
        self.globalKeywords = globalKeywords.map(Self.normalized).filter { !$0.isEmpty }
        self.roomKeywords = roomKeywords.map(Self.normalized).filter { !$0.isEmpty }
    }

    /// The three sources add up rather than override each other, so registering
    /// a word for one room never costs it the name and the words every room
    /// already answers to.
    public init(nickname: String?, globalKeywords: [String], policy: RoomPolicy) {
        self.init(
            nickname: nickname,
            globalKeywords: globalKeywords,
            roomKeywords: policy.responseKeywords
        )
    }

    /// Every word this room answers to, the name first, without repeats.
    public var all: [String] {
        var seen: Set<String> = []
        return ([nickname].compactMap { $0 } + globalKeywords + roomKeywords)
            .filter { seen.insert($0.lowercased()).inserted }
    }

    public var isEmpty: Bool { all.isEmpty }

    public func matches(_ text: String) -> Bool {
        matched(in: text) != nil
    }

    /// Which word made this a call. A screen that has to explain why a room
    /// answers — or why it never does — needs the word, not just a yes.
    public func matched(in text: String) -> String? {
        if let nickname, Self.callsByName(text, nickname) { return nickname }
        return (globalKeywords + roomKeywords).first { text.localizedCaseInsensitiveContains($0) }
    }

    /// `@` is how a name is typed in a room, not part of the name. Stored with
    /// the tag, the same word would stop matching a plain call by name.
    public static func normalized(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).drop { $0 == "@" })
            .trimmingCharacters(in: .whitespaces)
    }

    /// The nickname is held to a stricter rule than a keyword, because the user
    /// did not choose it.
    ///
    /// A keyword matches anywhere in the message: Korean particles attach
    /// straight onto a noun, so `달구봇아` has to count, and a word that fires
    /// too often is one the user typed and can delete. The nickname arrives on
    /// its own, and a short one — `민`, `Ann` — would answer messages that only
    /// happen to contain those letters, in a room nobody addressed. So it has to
    /// begin where a word begins and may only run on into Hangul: `달구지톡아`
    /// and `@달구지톡` are calls, `우리달구지톡` and `Announcement` are not.
    private static func callsByName(_ text: String, _ nickname: String) -> Bool {
        let haystack = text.lowercased()
        let needle = nickname.lowercased()
        var from = haystack.startIndex

        while let found = haystack.range(of: needle, range: from ..< haystack.endIndex) {
            if beginsAWord(haystack, at: found.lowerBound),
               !continuesAWord(haystack, at: found.upperBound) {
                return true
            }
            from = haystack.index(after: found.lowerBound)
        }
        return false
    }

    private static func beginsAWord(_ text: String, at index: String.Index) -> Bool {
        guard index > text.startIndex else { return true }
        let previous = text[text.index(before: index)]
        return !previous.isLetter && !previous.isNumber
    }

    /// Korean particles are letters too, so only a digit or a letter that is not
    /// Hangul means the name landed inside a longer word.
    private static func continuesAWord(_ text: String, at index: String.Index) -> Bool {
        guard index < text.endIndex else { return false }
        let next = text[index]
        guard next.isLetter || next.isNumber else { return false }
        return !next.isHangul
    }
}

private extension Character {
    /// Hangul syllables, and the jamo they are written with.
    var isHangul: Bool {
        unicodeScalars.allSatisfy { scalar in
            (0xAC00 ... 0xD7A3).contains(scalar.value)
                || (0x1100 ... 0x11FF).contains(scalar.value)
                || (0x3130 ... 0x318F).contains(scalar.value)
        }
    }
}
