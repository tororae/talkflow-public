import Foundation

/// A photo taken out of KakaoTalk's local media so the model can see what a
/// message was about.
///
/// It carries the message it came from because a picture with no place in the
/// conversation is just a picture: the prompt uses this to say who sent it and
/// when.
public struct MessagePhoto: Equatable, Sendable {
    public let messageID: String
    public let fileURL: URL

    public init(messageID: String, fileURL: URL) {
        self.messageID = messageID
        self.fileURL = fileURL
    }
}

/// The photos extracted for one model call, and the directory holding them.
///
/// The directory travels with the files so the whole lot can be removed in one
/// step. These are pictures out of someone's conversation, and nothing about
/// drafting a reply justifies leaving them on disk afterwards.
public struct MessagePhotoSet: Equatable, Sendable {
    public static let none = MessagePhotoSet(directoryURL: nil, photos: [])

    public let directoryURL: URL?
    public let photos: [MessagePhoto]

    public init(directoryURL: URL?, photos: [MessagePhoto]) {
        self.directoryURL = directoryURL
        self.photos = photos
    }

    public var isEmpty: Bool { photos.isEmpty }
}

/// Turns photo messages into files a provider can attach.
///
/// Extraction and cleanup are separate calls so the caller can `defer` the
/// cleanup: the files have to go whether the model answered, refused, or the
/// call failed. `discard` is deliberately not `async` — a caller cannot await
/// inside `defer`, and an unwaited cleanup is a cleanup that silently stops
/// happening.
public protocol MessagePhotoSource: Sendable {
    func photos(for messages: [ChatMessage], in room: ChatRoom) async -> MessagePhotoSet
    func discard(_ set: MessagePhotoSet)
}

/// Which photos of a conversation ride along with the reply request.
public enum MessagePhotoSelection {
    /// Photos attached to one model call.
    ///
    /// The context is 30 messages and every one of them could be a photo, so
    /// without a cap the price of a single reply is unbounded — in upload size,
    /// in image tokens, and in the extraction that runs before the call. Three
    /// covers what actually loses meaning today: a picture and the messages
    /// around it, or the short burst someone sends when one shot is not enough.
    /// Anything older than that is being discussed in words by the time the
    /// question arrives.
    public static let limit = 3

    /// The most recent photos of a conversation, oldest first.
    ///
    /// Recency wins because the message being judged is the newest one, and a
    /// photo from twenty messages ago is rarely what it answers.
    public static func candidates(
        in messages: [ChatMessage],
        limit: Int = MessagePhotoSelection.limit
    ) -> [ChatMessage] {
        Array(messages.filter { $0.kind == .photo }.suffix(limit))
    }
}
