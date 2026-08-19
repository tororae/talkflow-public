import Foundation

/// What this account said last, pulled out of the conversation and shown to the
/// model on its own.
///
/// The model already sees these — they sit in `<conversation>` marked 「나」, in
/// their proper place in the flow. That turned out not to be enough. Measured on
/// a real account: five consecutive replies in one room, every one a fresh remark
/// about the same 배달비 — 「또 그 얘기 시작이네」, 「아 3천원이면 차라리 걸어가서
/// 사 오지」, 「3천원 아끼려고 나가기도 귀찮고」. Each answered the message in
/// front of it. Together they read like nobody who has ever been in a
/// conversation. (원문 대신 같은 모양으로 옮겨 적었다. 카카오톡 원문은 저장소에
/// 두지 않는다.)
///
/// A line inside a transcript is something to read. The same line under a heading
/// that says 「내가 방금 한 말」 is something to check yourself against, and that
/// is the difference this exists for. The instruction not to repeat has something
/// concrete to point at instead of asking the model to find its own words in a
/// wall of other people's.
///
/// They stay in the transcript as well. Removing them would break the thread —
/// the replies are half of what was said — so this is a restatement, not a move.
public enum OwnRecentReplies {
    /// Enough to show a pattern, few enough that the block stays scannable. A
    /// repetition needs two to exist and three to be a habit.
    public static let limit = 3

    /// One line each. A long message pasted into the room would otherwise push
    /// the conversation itself out of the prompt to make room for a copy of
    /// something already in it.
    public static let characterLimit = 80

    /// The newest first, because that is the one most likely to be repeated.
    ///
    /// Text messages only. A photo or a sticker this account sent says nothing
    /// about the words it used, and 「사진」 repeated three times is a block that
    /// costs prompt space to say nothing.
    public static func from(_ messages: [ChatMessage]) -> [String] {
        messages
            .reversed()
            .filter { $0.isFromMe && $0.kind == .text }
            .map { bounded(ConversationFence.neutralised($0.body)) }
            .filter { !$0.isEmpty }
            .prefix(limit)
            .map { $0 }
    }

    /// Fenced like everything else that came out of a conversation. These are the
    /// account's own messages, but the words in them were written by a model
    /// reading untrusted input, and a closing tag smuggled through a reply would
    /// break the fence just as effectively as one smuggled through a message.
    private static func bounded(_ text: String) -> String {
        let line = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.count > characterLimit else { return line }
        return String(line.prefix(characterLimit - 1)) + "…"
    }
}
