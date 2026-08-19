import Foundation

public struct ChatMessage: Identifiable, Equatable, Sendable {
    /// KakaoTalk carries photos, emoticons, and system notices alongside text.
    /// Response policies only reason about text, so the rest collapses rather
    /// than leaking the source's type vocabulary.
    ///
    /// Photos are the one exception, because they are the only non-text kind the
    /// app can turn back into something a model reads. Left inside `attachment`
    /// they are indistinguishable from a room-renamed notice or an emoticon, and
    /// asking KakaoTalk for the picture behind those costs a process launch that
    /// returns nothing.
    public enum Kind: Equatable, Sendable {
        case text
        case photo
        case attachment
    }

    public let id: String
    public let chatRoomID: String
    public let sender: ChatMember
    public let body: String
    public let sentAt: Date
    public let kind: Kind
    public let isFromMe: Bool
    /// The message this one is a KakaoTalk 답장 to, if it is one.
    ///
    /// Replying to somebody names them without typing their name, so this is the
    /// one address a policy can read that needs nothing configured and cannot be
    /// coincidence — unlike a keyword, which the user has to register and which
    /// the message may only happen to contain.
    ///
    /// Nil for most messages: KakaoTalk leaves the column empty unless the sender
    /// picked a message to answer.
    public let replyToMessageID: String?

    /// What this message reads as when it is shown to someone or quoted into a
    /// prompt, rather than matched against a rule.
    ///
    /// Only text has a body worth printing. KakaoTalk keeps the word 사진 in a
    /// photo row's text column and a system notice's JSON in an attachment's, so
    /// printing `body` unconditionally puts one or the other in front of a
    /// person.
    public var readableBody: String {
        switch kind {
        case .text: body
        case .photo: "(사진)"
        case .attachment: "(사진 또는 이모티콘)"
        }
    }

    public init(
        id: String,
        chatRoomID: String,
        sender: ChatMember,
        body: String,
        sentAt: Date,
        kind: Kind = .text,
        isFromMe: Bool = false,
        replyToMessageID: String? = nil
    ) {
        self.id = id
        self.chatRoomID = chatRoomID
        self.sender = sender
        self.body = body
        self.sentAt = sentAt
        self.kind = kind
        self.isFromMe = isFromMe
        self.replyToMessageID = replyToMessageID
    }
}
