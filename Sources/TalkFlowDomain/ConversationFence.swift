import Foundation

/// The one token in a TalkFlow prompt that carries structure, and the rule that
/// keeps other text from carrying it too.
///
/// Its own type because it now runs in two directions. Going in, it stops a
/// message from closing the block it is quoted inside. Coming out, the model's
/// own words land in a record the user reads, and a record is the sort of thing
/// that is not a prompt right up until somebody hands one back to a model —
/// `AnsweredRun` already copies conversation text into records for that reason.
/// One definition, so the two directions cannot drift apart.
///
/// Scope is deliberately narrow: the fence tags, nothing else. Text that merely
/// reads like an instruction is still text, and a filter that guessed at intent
/// would mangle ordinary Korean while stopping nothing an attacker cannot spell
/// another way.
public enum ConversationFence {
    public static func neutralised(_ text: String) -> String {
        text
            .replacingOccurrences(of: "</conversation", with: "<\u{200B}/conversation")
            .replacingOccurrences(of: "<conversation", with: "<\u{200B}conversation")
    }
}
