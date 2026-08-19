import Foundation

/// 채팅방 요약 — the standing note about one room, carried into every reply
/// prompt so the model is not answering as somebody who just walked in.
///
/// The second of the three memory layers in `DESIGN.md` §5.3. The first, the
/// recent window, is thirty messages: in a friendship that has run for months
/// that is nearly nothing, and it cannot say who these people are to the user or
/// what was promised last week.
///
/// Three properties decide its shape.
///
/// **Editable.** The model drafts it and the user corrects it. "前 직장 동료,
/// 존댓말 유지" is something no amount of conversation makes derivable, and a
/// corrected note is a brief written by a human that the app then works from.
/// Whether a correction survives the next refresh is `isPinned`, a checkbox on the
/// room screen — not something inferred from having typed.
///
/// **Bounded.** It rides in every reply prompt, so its length is spent on every
/// call rather than once.
///
/// **Fenced.** It is model output derived from untrusted conversation, so a
/// message can try to write structure into it. Neutralised here, in the value
/// type, rather than at each place that renders it — the same reason
/// `ReplyDraft.usableDeclineReason` does it on the way into a record.
public struct ConversationSummary: Equatable, Sendable {
    /// Roughly eight to ten short Korean lines.
    ///
    /// Picked against what a call already carries: `ConversationWindow` gives the
    /// conversation itself 4000 characters, and a background note allowed to grow
    /// past a sixth of that starts outweighing what the people in the room
    /// actually said. It is also paid on every reply, unlike the conversation,
    /// which at least changes — a stale sentence in here is bought again on every
    /// single call.
    ///
    /// Enforced here as a backstop rather than as the only guard, like
    /// `AnsweringCondition`: the prompt asks the model for this length, and the
    /// edit field refuses a longer text where the user can read why.
    public static let characterLimit = 600

    public let accountFingerprint: String
    public let chatRoomID: String
    public let text: String
    public let updatedAt: Date
    /// Whether the refresh is allowed to rewrite this note. A checkbox on the room
    /// screen, and the only thing that stops a rewrite.
    ///
    /// This used to be inferred from having typed: saving an edit set a
    /// `isUserEdited` flag and the sweep skipped anything carrying it. Correcting
    /// one word was therefore a decision to freeze the note, which is not what
    /// anybody means by fixing a sentence — and for person notes there was no way
    /// back at all, since nothing in the app ever cleared the flag. Now editing is
    /// editing and stopping the refresh is a switch the user throws.
    public let isPinned: Bool
    /// The newest message folded in, and the anchor the next refresh starts from.
    ///
    /// An id rather than an instant. KakaoTalk's clock and ours are not the same
    /// clock — `ReplyEvaluationRequest.judgementScope` already works around the
    /// two disagreeing — and a summary that re-read a few minutes of history
    /// every time would pay for the same messages twice.
    public let coveredThroughMessageID: String?
    /// How many messages have gone into this note over all its refreshes, shown
    /// on the room screen as the range this was derived from (`DESIGN.md` §5.4).
    public let coveredMessageCount: Int

    public init(
        accountFingerprint: String,
        chatRoomID: String,
        text: String,
        updatedAt: Date,
        isPinned: Bool = false,
        coveredThroughMessageID: String? = nil,
        coveredMessageCount: Int = 0
    ) {
        self.accountFingerprint = accountFingerprint
        self.chatRoomID = chatRoomID
        self.text = String(ConversationFence.neutralised(text).prefix(Self.characterLimit))
        self.updatedAt = updatedAt
        self.isPinned = isPinned
        self.coveredThroughMessageID = coveredThroughMessageID
        self.coveredMessageCount = coveredMessageCount
    }

    /// Nothing but whitespace is no summary. A blank note would open a labelled
    /// section in every prompt that says nothing at the user's expense, and it
    /// must never replace a good one — see `isUsable`.
    public var isEmpty: Bool { text.allSatisfy(\.isWhitespace) }

    /// Whether this is worth storing or sending. A model that answers with an
    /// empty string has not summarised the room; it has produced a value that
    /// would erase the note already there.
    public var isUsable: Bool { !isEmpty }

    /// The same note after the user rewrote it.
    ///
    /// The anchor and the count carry over unchanged: the user corrected what the
    /// note *says*, not which messages it was built from, and resetting the
    /// anchor would make the next refresh re-read history already folded in.
    ///
    /// Pinning carries over too rather than being set. Typing is not a request to
    /// stop refreshing; the checkbox is.
    public func edited(_ newText: String, at moment: Date) -> ConversationSummary {
        ConversationSummary(
            accountFingerprint: accountFingerprint,
            chatRoomID: chatRoomID,
            text: newText,
            updatedAt: moment,
            isPinned: isPinned,
            coveredThroughMessageID: coveredThroughMessageID,
            coveredMessageCount: coveredMessageCount
        )
    }

    /// Whether a typed string would survive being stored. Asked by the edit
    /// field, which refuses the text rather than shortening it under the cursor —
    /// the bug the keyword box and the settings screen both shipped once.
    public static func exceedsLimit(_ text: String) -> Bool {
        text.count > characterLimit
    }
}
