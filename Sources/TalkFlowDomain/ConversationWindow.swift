import Foundation

/// How much conversation one model call is allowed to carry.
///
/// The bound used to be a message count on the fetch alone. A room that judges in
/// batches accumulates for minutes before it is asked anything, so one call now
/// has to survive whatever piled up — and thirty long messages are a very
/// different prompt from thirty short ones.
///
/// The oldest go first. The judgement is about the newest message, and what falls
/// off the back has usually been answered or restated by the people talking.
/// Condensing the dropped part — a real conversation summary — is a separate
/// feature; until it exists the prompt says how many messages are missing instead
/// of implying it saw the whole thread.
public enum ConversationWindow {
    public static let messageLimit = 30
    /// Characters rather than tokens: the provider decides what a token is, and
    /// this only has to stop one call from growing without bound.
    public static let characterBudget = 4000

    public struct Bounded: Equatable, Sendable {
        /// Chronological, oldest first, like everything else that carries a
        /// conversation.
        public let messages: [ChatMessage]
        public let omittedCount: Int

        public init(messages: [ChatMessage], omittedCount: Int) {
            self.messages = messages
            self.omittedCount = omittedCount
        }
    }

    public static func bounded(
        _ messages: [ChatMessage],
        messageLimit: Int = ConversationWindow.messageLimit,
        characterBudget: Int = ConversationWindow.characterBudget
    ) -> Bounded {
        var kept: [ChatMessage] = []
        var used = 0

        for message in messages.suffix(messageLimit).reversed() {
            // The newest message is the one being answered, so it is kept
            // whatever it costs. A prompt without it answers nothing.
            if !kept.isEmpty, used + message.body.count > characterBudget { break }
            used += message.body.count
            kept.append(message)
        }

        return Bounded(messages: kept.reversed(), omittedCount: messages.count - kept.count)
    }
}
