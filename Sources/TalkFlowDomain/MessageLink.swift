import Foundation

/// A web page opened from a link a conversation carried, so the model can answer
/// about what the page says instead of guessing from the address.
///
/// The text is already extracted and bounded by the reader; nothing here fetches.
/// It carries the message it came from for the same reason a photo does — a page
/// with no place in the conversation is just a page.
public struct MessageLink: Equatable, Sendable {
    public let messageID: String
    public let url: URL
    /// The readable text of the page, already rendered and length-capped.
    public let text: String

    public init(messageID: String, url: URL, text: String) {
        self.messageID = messageID
        self.url = url
        self.text = text
    }
}

/// One URL a conversation carried, before anything is fetched.
public struct LinkCandidate: Equatable, Sendable {
    public let messageID: String
    public let url: URL

    public init(messageID: String, url: URL) {
        self.messageID = messageID
        self.url = url
    }
}

/// Opens the links in a conversation and returns their text.
///
/// The app fetches and renders; the model never browses. Whatever a page turns
/// out to hold is untrusted the same as a chat message — the reply prompt frames
/// it so, because a page the account was pointed at can carry instructions too.
public protocol MessageLinkSource: Sendable {
    func links(for messages: [ChatMessage], in room: ChatRoom) async -> [MessageLink]
}

/// Which links of a conversation are worth opening, and the cap on how many.
public enum MessageLinkSelection {
    /// Opening a page is a network fetch and a full render — the most expensive
    /// context this app gathers, and it runs inside a serial sweep, so a high cap
    /// would slow every other room. Two covers the link just pasted and the one
    /// before it, which is almost always what a question is about.
    public static let limit = 2

    /// The most recent http(s) URLs in a conversation, oldest first, each URL
    /// once. Read off message bodies with the system link detector, so a URL
    /// typed without a scheme ("makta.net") is still found and normalised, and a
    /// message that is nothing but a link is treated the same as one with a link
    /// in a sentence.
    public static func candidates(
        in messages: [ChatMessage],
        limit: Int = MessageLinkSelection.limit
    ) -> [LinkCandidate] {
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        ) else {
            return []
        }

        var candidates: [LinkCandidate] = []
        var seen = Set<String>()
        for message in messages {
            let body = message.body
            guard !body.isEmpty else { continue }
            let range = NSRange(body.startIndex..<body.endIndex, in: body)
            for match in detector.matches(in: body, options: [], range: range) {
                guard let url = match.url,
                      let scheme = url.scheme?.lowercased(),
                      scheme == "http" || scheme == "https"
                else { continue }
                let key = url.absoluteString
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                candidates.append(LinkCandidate(messageID: message.id, url: url))
            }
        }
        return Array(candidates.suffix(limit))
    }
}
