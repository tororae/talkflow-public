import Foundation

/// The run of conversation one judgement is a response to.
///
/// Not the prompt window. That is the surrounding thirty messages the model was
/// handed for context, and it is counted on its own. This is the narrower thing:
/// the messages the answer answers.
///
/// One trigger message used to stand for it, and two mechanisms turned that into
/// a lie. 뒷말 대기 folds whatever arrives during its pause into the same
/// judgement, and a room on 판단 주기 is asked once about everything that piled
/// up since the previous call. In both cases the record named the last message
/// and the reply beside it did not follow from that message.
///
/// Copied at judgement time, like the trigger text it grew out of. Ids stop
/// resolving the moment the archive is pruned or the account changes, and this
/// exists to be read months later.
public struct AnsweredRun: Equatable, Sendable, Codable {
    /// One message, as it read when the judgement was made.
    public struct Line: Equatable, Sendable, Codable {
        public let messageID: String
        /// The name shown then. People are renamed and members leave, so the
        /// record keeps the name the reader would have seen.
        public let senderName: String
        public let sentAt: Date
        public let body: String

        public init(messageID: String, senderName: String, sentAt: Date, body: String) {
            self.messageID = messageID
            self.senderName = senderName
            self.sentAt = sentAt
            self.body = body
        }
    }

    /// Oldest first, in the order they were said.
    public let lines: [Line]

    /// How many older messages of the run the record left out.
    ///
    /// Carried rather than dropped quietly: part of a run displayed as the whole
    /// of one is the same misreading this type exists to end, in a smaller size.
    public let omittedCount: Int

    public init(lines: [Line], omittedCount: Int = 0) {
        self.lines = lines
        self.omittedCount = omittedCount
    }

    /// As many lines as a person will read off one pane. A five-minute interval
    /// in an active room accumulates more than this, and the record is for
    /// reading rather than for replaying the room — past twenty lines nobody
    /// reads it, and the count of what came off says the rest honestly.
    public static let messageLimit = 20

    /// One pasted block outweighs twenty sentences, so length is bounded too.
    /// Characters rather than tokens, for the same reason the prompt uses them:
    /// this only has to keep one row from growing without bound.
    public static let characterBudget = 2000

    /// The run answered by a judgement that started at `anchorID`.
    ///
    /// One rule for both ways a run comes about, because both name the same
    /// thing — the message the judgement started from, and everything said
    /// after it. 즉시 starts at the message that triggered the call, and the
    /// wait for 뒷말 adds to the end rather than moving that start. 주기마다
    /// starts at the oldest message accumulated since the previous call.
    public static func from(_ conversation: [ChatMessage], startingAt anchorID: String?) -> AnsweredRun {
        // Trimmed by the rule the prompt window already uses: oldest off first,
        // the newest kept whatever it costs, and what came off counted. Its own
        // numbers, because a person reading a record and a model reading a
        // prompt do not take the same amount.
        let bounded = ConversationWindow.bounded(
            messages(in: conversation, startingAt: anchorID),
            messageLimit: messageLimit,
            characterBudget: characterBudget
        )
        return AnsweredRun(
            lines: bounded.messages.map(Line.init),
            omittedCount: bounded.omittedCount
        )
    }

    private static func messages(in conversation: [ChatMessage], startingAt anchorID: String?) -> [ChatMessage] {
        guard let anchorID else { return Array(conversation.suffix(1)) }
        guard let start = conversation.firstIndex(where: { $0.id == anchorID }) else {
            // The anchor is older than anything still held, so everything left
            // is inside the run. Answering only the last message here would
            // shrink a long batch to one line because its opening scrolled off.
            return conversation
        }
        return Array(conversation[start...])
    }
}

extension AnsweredRun.Line {
    init(_ message: ChatMessage) {
        self.init(
            messageID: message.id,
            // The word the prompt uses for the account's own messages. A batch
            // carries them, and a display name that means nothing to the person
            // reading their own record is worse than none.
            senderName: message.isFromMe ? "나" : message.sender.displayName,
            sentAt: message.sentAt,
            body: message.readableBody
        )
    }
}
