import Foundation
import TalkFlowDomain

/// Rewrites a room's 채팅방 요약 through the Codex CLI the user is already signed
/// into.
///
/// The same lockdown as a reply — read-only sandbox, `--ephemeral`, a schema the
/// answer is parsed against — because the input is the same input: somebody's
/// conversation. What differs is the shape that comes back, which is why this is
/// not a second intent inside `CodexReplyGenerator`: that one's schema is built
/// around a decision, and a note arriving with a `should_reply` beside it would be
/// one read away from becoming a message.
public struct CodexSummaryWriter: ConversationSummaryWriter {
    public enum WriteError: LocalizedError {
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
    /// Read on every call, for the reason the reply generator reads it on every
    /// call: this one is started at launch and refreshes rooms for days.
    private let model: @Sendable () async -> AIModelChoice
    private let promptBuilder = ConversationSummaryPromptBuilder()

    /// `people` is required and may be empty, for the reason `decline_reason` is
    /// required on the reply schema: `additionalProperties: false` rejects
    /// anything not listed, so a field that only matters sometimes has to be
    /// present and empty rather than absent.
    static let responseSchema = """
    {
      "type": "object",
      "properties": {
        "summary": { "type": "string" },
        "people": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "sender_id": { "type": "string" },
              "note": { "type": "string" },
              "links": {
                "type": "array",
                "items": {
                  "type": "object",
                  "properties": {
                    "label": { "type": "string" },
                    "url": { "type": "string" },
                    "relation": { "type": "string", "enum": ["made", "shared", "unknown"] },
                    "last_mentioned": { "type": "boolean" }
                  },
                  "required": ["label", "url", "relation", "last_mentioned"],
                  "additionalProperties": false
                }
              }
            },
            "required": ["sender_id", "note", "links"],
            "additionalProperties": false
          }
        }
      },
      "required": ["summary", "people"],
      "additionalProperties": false
    }
    """

    public init(
        fileManager: FileManager = .default,
        model: @escaping @Sendable () async -> AIModelChoice
    ) {
        executableURL = CodexCLIConnection.findExecutable(using: fileManager)
        self.model = model
    }

    public func writeSummary(_ request: ConversationSummaryRequest) async throws -> ConversationSummaryResult {
        guard let executableURL else { throw WriteError.executableMissing }

        let workspace = try CodexWorkspace(
            schema: Self.responseSchema,
            modelID: await model().modelID
        )
        defer { workspace.destroy() }

        // No photos, ever. A note about a room is text, and spending an upload on
        // a call nobody is waiting for would widen what leaves the Mac for a
        // feature the user was not asked about picture by picture.
        let arguments = ["exec"] + workspace.lockedDownArguments
        let prompt = promptBuilder.prompt(for: request)
        let result = await Task.detached {
            CommandLineTool(executableURL: executableURL).run(arguments: arguments, input: prompt)
        }.value

        guard let result, result.exitCode == 0 else {
            throw WriteError.callFailed(Self.failureDetail(result?.output))
        }
        guard let data = try? Data(contentsOf: workspace.responseURL),
              let payload = try? JSONDecoder().decode(CodexSummaryPayload.self, from: data)
        else {
            throw WriteError.malformedResponse
        }
        return ConversationSummaryResult(
            summary: payload.summary,
            people: (payload.people ?? []).map {
                PersonNoteUpdate(
                    senderID: $0.senderID,
                    note: $0.note,
                    links: ($0.links ?? []).map {
                        PersonLink(
                            label: $0.label,
                            url: $0.url,
                            relation: $0.relation.flatMap(PersonLink.Relation.init(rawValue:)) ?? .unknown,
                            // Stamped by the caller, which is the only place that
                            // knows when "이번 대화" was. The model is asked whether
                            // the link came up, never when.
                            lastMentionedAt: ($0.lastMentioned ?? false) ? Date() : nil
                        )
                    }
                )
            }
        )
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

struct CodexSummaryPayload: Decodable {
    let summary: String
    /// Optional in the decoder though the schema requires it, so a provider
    /// answering in the old shape is still understood rather than thrown away as
    /// malformed. Absent reads as "learned nothing about anybody", which is what
    /// every room did before this existed.
    let people: [Person]?

    struct Person: Decodable {
        let senderID: String
        let note: String
        let links: [Link]?

        enum CodingKeys: String, CodingKey {
            case senderID = "sender_id"
            case note
            case links
        }
    }

    struct Link: Decodable {
        let label: String
        let url: String
        /// Optional in the decoder though the schema requires it. An answer
        /// without it is a link whose provenance nobody stated, which is exactly
        /// what `unknown` means — better than refusing the whole refresh.
        let relation: String?
        let lastMentioned: Bool?

        enum CodingKeys: String, CodingKey {
            case label
            case url
            case relation
            case lastMentioned = "last_mentioned"
        }
    }
}
