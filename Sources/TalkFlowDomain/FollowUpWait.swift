import Foundation

/// What happens when the model says the person is not finished talking.
///
/// People routinely split one thought across messages, and answering the first
/// half reads worse than answering a few seconds late. Deciding *whether* this
/// is one of those moments is a reading of the conversation, so it is asked of
/// the thing already reading the conversation — `ReplyDraft.expectsMore` — and
/// this type only holds how long to wait and how many times.
///
/// Two of the app's own guesses were removed to get here. The first was local:
/// a list of Korean connectives and a five-second burst window, which decided
/// before the model was called whether to pause. The second was worse — the send
/// gate cancelled any finished draft whose subject had spoken again, which cost
/// 113 drafts in three days and never converged, because redrafting took eight
/// seconds and the same person could speak inside that too.
public enum FollowUpWait {
    /// How long one round waits before reading the room again.
    ///
    /// Long enough to collect the rest of what somebody is typing, short enough
    /// that the answer still belongs to the conversation it answers.
    public static let defaultDelay: TimeInterval = 10

    /// How many times the model may be asked in total for one reply.
    ///
    /// The model can ask to wait again — somebody writing a long thought in
    /// pieces genuinely needs it — but not forever. On the last round the answer
    /// goes out whatever the flag says, so a provider that always sets it costs
    /// a bounded delay rather than a reply that never arrives.
    public static let maximumRounds = 3

    /// Whether another round is allowed after this one.
    ///
    /// `round` counts calls already made, so the first answer arrives with
    /// `round == 1`.
    public static func mayWaitAgain(round: Int, reply: ReplyDraft) -> Bool {
        reply.wantsFollowUp && round < maximumRounds
    }

    /// What the record says about a wait that has just finished.
    public static func note(round: Int) -> String {
        "모델이 뒷말을 예상해 \(Int(defaultDelay.rounded()))초 기다렸습니다. (\(round)번째)"
    }
}
