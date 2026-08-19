import Foundation

/// 답변 조건 — what the user says deserves an answer, in their own words.
///
/// Free text rather than another set of levels. It replaces the wording the app
/// used to write for 자발 개입 낮음 ("답을 기다리는 말일 때만 답하세요"), which was the
/// app guessing at what a cautious room wanted. This is the user saying it:
/// "일정 잡는 얘기랑 나한테 직접 묻는 것 위주로. 잡담엔 끼지 마."
///
/// It goes into the prompt, so it is the quality lever — it changes *what* gets
/// answered and never how often the model is asked. The two settings that change
/// that are 끼어들기 확률 and 판단 주기, and the help cards keep the three apart.
///
/// Trusted input in the only sense that matters: the user is the principal here,
/// and telling the model what to answer is the whole point, so nothing tries to
/// detect "instructions" in it. It is still run through `ConversationFence` on the
/// way into a prompt — see `ReplyPromptBuilder` for why a trusted string still
/// may not write the one token that carries structure.
public struct AnsweringCondition: Equatable, Sendable {
    /// A few sentences. Long enough for several rules in the user's own words —
    /// the example above is 36 characters — and short enough that the condition
    /// cannot outweigh the rule block the prompt writes around it, or quietly
    /// grow what every call costs.
    ///
    /// Enforced here as a backstop rather than as the only guard. The field
    /// refuses a longer text where the user can read why; this keeps anything
    /// that reaches the store or a prompt inside the same bound, including a row
    /// nobody typed.
    public static let characterLimit = 300

    public let text: String

    /// Kept exactly as typed, apart from the length cap.
    ///
    /// Deliberately not trimmed. The room screen writes this on every keystroke
    /// and hands the stored value straight back to the field, so a value type
    /// that tidied the ends would delete the space in "일정 " as it was typed and
    /// make the next word impossible to start. That is the bug the keyword box
    /// and the whole settings screen already shipped once. Whitespace is asked
    /// about rather than removed — see `isEmpty`.
    ///
    /// The cap is a backstop that the fields never reach: they refuse a longer
    /// text where the user can read why, rather than shortening it in place.
    public init(_ text: String) {
        self.text = String(text.prefix(Self.characterLimit))
    }

    /// No condition at all, which is where every install starts: the model judges
    /// by its own reading, as it did before this setting existed.
    ///
    /// Not called `none`. A room's override is an `AnsweringCondition?`, and in
    /// that context `.none` binds to `Optional.none` — so writing what looks like
    /// "이 방은 조건 없이" would silently mean "follow 설정" instead, which is the
    /// other value entirely.
    public static let empty = AnsweringCondition("")

    /// Nothing but whitespace counts as no condition. A field holding a stray
    /// space is a field the user cleared, and an otherwise empty 답변 조건 section
    /// in the prompt would say nothing at the model's expense.
    public var isEmpty: Bool { text.allSatisfy(\.isWhitespace) }

    /// Whether a typed string would survive being turned into a condition. Asked
    /// by the fields, which refuse the text rather than shortening it under the
    /// cursor. Counted the same way the cap counts, so the two cannot disagree
    /// about a text sitting exactly on the limit.
    public static func exceedsLimit(_ text: String) -> Bool {
        text.count > characterLimit
    }
}
