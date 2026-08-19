import Foundation

/// When a room's note is worth rewriting, and which messages the rewrite reads.
///
/// The whole point of the layer is that it stays cheap as a room grows. A new
/// note is `model(old note + what has happened since)`, never `model(everything)`
/// — the room measured largest here holds 1,492 messages over two days, and the
/// account was switched recently so that history is young rather than typical.
/// Re-reading it on each refresh would make the cost of remembering a room grow
/// with the room, which is the one thing this must not do.
public enum ConversationSummaryRefresh {
    /// How far back a room with no note reads.
    ///
    /// Four reply windows. Enough to establish who is in the room and what is
    /// going on — the smallest real room here holds 58 messages, so most rooms are
    /// read whole on their first pass anyway — and a fixed ceiling for the ones
    /// that are not. A bootstrap that read "all of it" would be a single enormous
    /// call whose size is decided by how long the user has had KakaoTalk.
    public static let historyLimit = 120

    /// The character ceiling on one refresh call, twice what a reply carries.
    ///
    /// A reply is a live call in a room somebody is waiting on; this one happens
    /// a few times a day and exists to compress. Same mechanism either way:
    /// `ConversationWindow` drops the oldest and says how many it dropped.
    public static let characterBudget = 8000

    /// New messages that make a refresh due.
    ///
    /// Larger than the reply window on purpose. Refreshing more often than the
    /// window turns over would mostly re-summarise text the reply prompt is still
    /// carrying verbatim, which is paying twice for the same messages. At this
    /// threshold the busiest room measured here — about 750 messages a day —
    /// costs some 19 refreshes a day against up to 750 reply judgements, so the
    /// layer adds a few percent rather than a second bill.
    public static let messageThreshold = 40

    /// How long a note may stand before one new message is enough to refresh it.
    ///
    /// The quiet rooms are the reason. A room that gets ten messages a week would
    /// never reach the count, and its note would still be describing last month
    /// — which in a room that slow is exactly where the standing context matters
    /// most, because the recent window covers weeks and still says nothing.
    public static let staleAfter: TimeInterval = 86_400

    /// Everything after the message the note already covers.
    ///
    /// An anchor that is not in the slice means the room moved further than
    /// `historyLimit` since the last refresh. The whole slice is new as far as
    /// this can tell, and reading further back to close the gap is the unbounded
    /// read this type exists to avoid — the prompt says how many messages were
    /// dropped instead of pretending it saw them.
    public static func newMessages(
        in messages: [ChatMessage],
        after anchor: String?
    ) -> [ChatMessage] {
        guard let anchor, let index = messages.lastIndex(where: { $0.id == anchor }) else {
            return messages
        }
        return Array(messages[messages.index(after: index)...])
    }

    /// Whether the sweep should spend a call on this room now.
    ///
    /// A hand-edited note is never due. The sweep runs behind the user's back, and
    /// the one failure this feature must not have is somebody's correction
    /// disappearing without anyone pressing anything. The button on the room
    /// screen refreshes it instead, which is the user asking.
    public static func isDue(
        _ summary: ConversationSummary?,
        newMessageCount: Int,
        now: Date
    ) -> Bool {
        // Nothing to fold in. Asking the model to summarise the summary it just
        // wrote costs a call and can only lose detail.
        guard newMessageCount > 0 else { return false }
        guard let summary else { return newMessageCount >= messageThreshold }
        guard !summary.isPinned else { return false }
        if newMessageCount >= messageThreshold { return true }
        return now.timeIntervalSince(summary.updatedAt) >= staleAfter
    }
}
