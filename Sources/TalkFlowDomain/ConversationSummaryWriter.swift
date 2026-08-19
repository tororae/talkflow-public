import Foundation

public struct ConversationSummaryRequest: Sendable {
    public let room: ChatRoom
    /// What the note says now, or nil on a room being summarised for the first
    /// time. This is what makes the refresh incremental: the model is handed its
    /// own earlier answer rather than the history that produced it.
    public let previous: ConversationSummary?
    /// Only what has happened since `previous` was written. Chronological, oldest
    /// first, like everything else that carries a conversation.
    public let newMessages: [ChatMessage]
    /// How many older messages were dropped to keep this call bounded. Told to
    /// the model for the same reason the reply prompt tells it: a thread that
    /// starts mid-argument reads as a whole one.
    public let omittedMessageCount: Int
    /// What is already known about the people this call may write about, and the
    /// list of who those people are.
    ///
    /// Empty when the room does not take part in 사람 기억, which is every room
    /// until somebody turns it on. A person with no note yet appears here with an
    /// empty one, because the model has to be told they are eligible — asked to
    /// write about "whoever seems important" it would pick, and picking is
    /// exactly the judgement this list exists to keep out of the prompt.
    public let people: [PersonNote]

    public init(
        room: ChatRoom,
        previous: ConversationSummary?,
        newMessages: [ChatMessage],
        omittedMessageCount: Int = 0,
        people: [PersonNote] = []
    ) {
        self.room = room
        self.previous = previous
        self.newMessages = newMessages
        self.omittedMessageCount = omittedMessageCount
        self.people = people
    }
}

/// What one refresh produced: the room's note, and whatever it learned about the
/// people in it.
///
/// One result from one call, which is the whole reason 사람 기억 costs nothing.
/// This call already reads the room's recent conversation, already runs on the
/// right cadence — forty new messages or a day — and already holds the previous
/// text. Asking a second time for the same material would have doubled the only
/// part of this app that spends money without anybody speaking.
public struct ConversationSummaryResult: Equatable, Sendable {
    public let summary: String
    public let people: [PersonNoteUpdate]

    public init(summary: String, people: [PersonNoteUpdate] = []) {
        self.summary = summary
        self.people = people
    }
}

/// One person's note as a refresh rewrote it.
public struct PersonNoteUpdate: Equatable, Sendable {
    public let senderID: String
    public let note: String
    public let links: [PersonLink]

    public init(senderID: String, note: String, links: [PersonLink] = []) {
        self.senderID = senderID
        self.note = note
        self.links = links
    }
}

/// Rewrites a room's standing note.
///
/// A port of its own rather than a second intent on `ReplyGenerator`. That one
/// answers "답할지, 그리고 뭐라고" and its schema is built around that pair; this
/// returns prose and never a decision. Sharing the shape would mean a summary
/// arriving with a `should_reply` nobody reads, and the first time somebody did
/// read it a note would turn into a message.
public protocol ConversationSummaryWriter: Sendable {
    func writeSummary(_ request: ConversationSummaryRequest) async throws -> ConversationSummaryResult
}
