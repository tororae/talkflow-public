import Foundation
import TalkFlowDomain

/// Generates reply drafts through the Codex CLI the user is already signed into.
///
/// The call is deliberately locked down: a read-only sandbox so the model cannot
/// run anything, `--ephemeral` so conversation text is not left in Codex's
/// session history, and a JSON schema so the answer is parsed rather than read.
public struct CodexReplyGenerator: ReplyGenerator {
    public enum GenerationError: LocalizedError {
        case executableMissing
        case callFailed(String)
        case malformedResponse

        public var errorDescription: String? {
            switch self {
            case .executableMissing: "Codex CLI를 찾을 수 없습니다."
            case let .callFailed(detail): "Codex 호출에 실패했습니다. \(detail)"
            case .malformedResponse: "Codex 응답을 이해하지 못했습니다."
            }
        }
    }

    private let executableURL: URL?
    /// Read on every call rather than captured once, the way the sender reads the
    /// send consent. The pipeline is built at launch and runs for days, so a
    /// captured value would have 설정 show one model while another kept answering
    /// until the app was restarted.
    private let model: @Sendable () async -> AIModelChoice
    private let promptBuilder = ReplyPromptBuilder()
    /// Answering a message and opening a subject are different prompts on the
    /// same call: same lockdown, same schema, same parse. Only the words differ.
    private let openerPromptBuilder = ConversationOpenerPromptBuilder()
    /// And the third: telling a room that this account's own availability moved.
    /// Same lockdown, same schema, same parse again — the decline this one leans
    /// on is the one the other two already use.
    private let announcementPromptBuilder = StateAnnouncementPromptBuilder()

    /// The contract the answer is parsed against, kept next to the type that
    /// decodes it so a renamed key cannot pass review as two separate edits.
    ///
    /// `decline_reason` is nullable and required for the same reason `reply_text`
    /// is: the schema rejects anything it does not list, so a field that only
    /// means something on one branch has to be present and null on the other
    /// rather than absent. Adding it costs the true case one `null`.
    static let responseSchema = """
    {
      "type": "object",
      "properties": {
        "should_reply": { "type": "boolean" },
        "reply_mode": { "type": "string", "enum": ["mention", "direct_question", "spontaneous"] },
        "confidence": { "type": "string", "enum": ["low", "medium", "high"] },
        "reply_text": { "type": ["string", "null"] },
        "decline_reason": { "type": ["string", "null"] },
        "expects_more": { "type": "boolean" },
        "needs_web_search": { "type": "boolean" },
        "search_topic": { "type": ["string", "null"] },
        "ack_message": { "type": ["string", "null"] }
      },
      "required": ["should_reply", "reply_mode", "confidence", "reply_text", "decline_reason", "expects_more", "needs_web_search", "search_topic", "ack_message"],
      "additionalProperties": false
    }
    """

    /// No default for `model`. A call that forgot it would silently answer with
    /// whatever some other project left in `~/.codex/config.toml`, which is the
    /// thing this argument exists to stop.
    public init(
        fileManager: FileManager = .default,
        model: @escaping @Sendable () async -> AIModelChoice
    ) {
        executableURL = CodexCLIConnection.findExecutable(using: fileManager)
        self.model = model
    }

    public func generateReply(_ request: ReplyDraftRequest) async throws -> ReplyDraft {
        guard let executableURL else { throw GenerationError.executableMissing }

        let prompt = switch request.intent {
        case .reply: promptBuilder.prompt(for: request)
        case .openConversation: openerPromptBuilder.prompt(for: request)
        case let .announce(announcement):
            announcementPromptBuilder.prompt(for: request, announcing: announcement)
        }
        let workspace = try CodexWorkspace(
            schema: Self.responseSchema,
            modelID: await model().modelID
        )
        defer { workspace.destroy() }

        let arguments = Self.arguments(
            workspace: workspace,
            photos: request.photos,
            webSearch: request.searchStage.toolEnabled
        )
        let result = await Task.detached {
            CommandLineTool(executableURL: executableURL).run(arguments: arguments, input: prompt)
        }.value

        guard let result, result.exitCode == 0 else {
            throw GenerationError.callFailed(Self.failureDetail(result?.output))
        }
        guard let data = try? Data(contentsOf: workspace.responseURL),
              let payload = try? JSONDecoder().decode(CodexReplyPayload.self, from: data),
              var draft = payload.draft
        else {
            throw GenerationError.malformedResponse
        }
        draft.webSearchCount = Self.webSearchCount(in: result.output)
        return draft
    }

    /// How many web searches Codex ran, counted off the progress it prints.
    ///
    /// Codex writes one `web search: <query>` line per query it issues, even
    /// without `--json`, so the count comes off the output the call already
    /// captures — no second output contract to keep, and a format this version
    /// no longer prints reads as zero rather than a wrong number. Only lines that
    /// carry a query count: the tool also prints blank `web search:` markers for
    /// its own begin steps, and those are not searches the user needs to see.
    static func webSearchCount(in output: String?) -> Int {
        guard let output else { return 0 }
        return output
            .split(separator: "\n")
            .filter { line in
                guard let marker = line.range(of: "web search:") else { return false }
                return !line[marker.upperBound...].trimmingCharacters(in: .whitespaces).isEmpty
            }
            .count
    }

    /// Photos are the one part of a conversation that cannot go over stdin, so
    /// they go as file paths instead. A path is not the content — the pictures
    /// live in a directory the caller deletes when this returns — so the rule
    /// that keeps conversation text out of process arguments still holds.
    ///
    /// They are listed first because `--image` takes a list: anything after it
    /// that does not look like a flag is read as another file name, and the `-`
    /// that tells Codex to read the prompt from stdin is exactly that. The order
    /// is the order the prompt numbers them in.
    private static func arguments(
        workspace: CodexWorkspace,
        photos: [MessagePhoto],
        webSearch: Bool
    ) -> [String] {
        var arguments = ["exec"]
        for photo in photos {
            arguments.append(contentsOf: ["--image", photo.fileURL.path])
        }
        // Only when the room turned it on. `web_search` is a server-side Responses
        // tool, so it does not loosen the read-only sandbox below — the model
        // still cannot run or write anything locally, it only gains a way to look
        // something up. Placed before `lockedDownArguments`, whose trailing `-`
        // must stay the last argument.
        if webSearch {
            arguments.append(contentsOf: ["-c", "tools.web_search=true"])
        }
        arguments.append(contentsOf: workspace.lockedDownArguments)
        return arguments
    }

    /// Codex prints progress before any error, and the tail is the part that says
    /// what went wrong.
    private static func failureDetail(_ output: String?) -> String {
        guard let output else { return "실행하지 못했습니다." }
        let lines = output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.suffix(2).joined(separator: " ")
    }
}

struct CodexReplyPayload: Decodable {
    let shouldReply: Bool
    let replyMode: String
    let confidence: String
    let replyText: String?
    /// Optional in the decoder even though the schema requires it, so a provider
    /// that answers in the old shape is still understood rather than thrown away
    /// as malformed. A missing reason reads the same as no reason.
    let declineReason: String?
    /// Optional for the same reason, and absent reads as false — send it. The
    /// safe default here is the one that delivers: a provider that never sets
    /// this behaves exactly as every provider did before the field existed.
    let expectsMore: Bool?
    /// Set when the model wants to look something up before answering. Optional
    /// like the others so a provider that never defers still decodes.
    let needsWebSearch: Bool?
    let searchTopic: String?
    let ackMessage: String?

    enum CodingKeys: String, CodingKey {
        case shouldReply = "should_reply"
        case replyMode = "reply_mode"
        case confidence = "confidence"
        case replyText = "reply_text"
        case declineReason = "decline_reason"
        case expectsMore = "expects_more"
        case needsWebSearch = "needs_web_search"
        case searchTopic = "search_topic"
        case ackMessage = "ack_message"
    }

    var draft: ReplyDraft? {
        guard let mode = ReplyTrigger(rawValue: Self.normalized(replyMode)),
              let confidence = ReplyDraft.Confidence(rawValue: confidence)
        else {
            return nil
        }
        return ReplyDraft(
            shouldReply: shouldReply,
            mode: mode,
            confidence: confidence,
            text: replyText,
            declineReason: declineReason,
            expectsMore: expectsMore ?? false,
            needsWebSearch: needsWebSearch ?? false,
            searchTopic: searchTopic,
            ackMessage: ackMessage
        )
    }

    /// The schema speaks snake_case; the domain speaks camelCase.
    private static func normalized(_ mode: String) -> String {
        mode == "direct_question" ? "directQuestion" : mode
    }
}
