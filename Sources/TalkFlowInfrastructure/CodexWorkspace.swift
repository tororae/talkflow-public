import Foundation

/// A throwaway directory holding the schema Codex validates against and the file
/// it writes its final message into.
///
/// Takes the schema rather than owning one, because two different calls go out
/// through this now: a reply, which comes back as a decision plus text, and a
/// 채팅방 요약, which comes back as prose. Same lockdown either way — that part is
/// not the caller's to vary.
struct CodexWorkspace {
    let directoryURL: URL
    /// What `-m` should be given, or nil to leave the flag off entirely and let
    /// `~/.codex/config.toml` pick. Carried here rather than added by each caller
    /// for the same reason the lockdown flags are: 답장 and 채팅방 요약 are the
    /// user's two AI calls, and a picker that only reached one of them would have
    /// the 설정 screen naming a model that half the calls ignore.
    let modelID: String?

    var schemaURL: URL { directoryURL.appending(path: "schema.json") }
    var responseURL: URL { directoryURL.appending(path: "response.json") }

    init(schema: String, modelID: String?) throws {
        directoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "talkflow-codex-\(UUID().uuidString)")
        self.modelID = modelID
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data(schema.utf8).write(to: schemaURL)
    }

    func destroy() {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    /// The flags that make a call safe to run against somebody's conversation: a
    /// read-only sandbox so the model cannot act, `--ephemeral` so the text is not
    /// left in Codex's session history, and a schema so the answer is parsed
    /// rather than read.
    ///
    /// Shared so that a second kind of call cannot quietly ship with one of them
    /// missing. The conversation itself never appears here — process arguments are
    /// visible to anything on the machine — and goes over stdin.
    ///
    /// `--model` rides along, and is the one entry a user chose rather than one
    /// TalkFlow insists on. Unchosen it is absent, not empty: the CLI takes an id
    /// it does not know without complaint and only the request fails, so the
    /// difference between "no flag" and "a blank flag" is the difference between
    /// working and every reply coming back unreadable.
    var lockedDownArguments: [String] {
        var arguments = [
            "--ephemeral",
            "--skip-git-repo-check",
            "--sandbox", "read-only",
            "--color", "never",
            "--cd", directoryURL.path,
            "--output-schema", schemaURL.path,
            "--output-last-message", responseURL.path
        ]
        if let modelID {
            arguments.append(contentsOf: ["--model", modelID])
        }
        // Last, always. `-` means "read the prompt from stdin", and anything that
        // takes a list of values — `--image` does — swallows it as a file name.
        arguments.append("-")
        return arguments
    }
}
