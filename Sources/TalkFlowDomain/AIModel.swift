import Foundation

/// One model TalkFlow can ask Codex for.
///
/// `id` is exactly what `codex exec -m` takes and is passed through as typed
/// here. The other two are for the screen, and are the CLI's own words rather
/// than ours: whether a model is the fast one or the frontier one is the
/// provider's claim to make, not TalkFlow's.
public struct AIModel: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    /// One line. The picker is scanned, not studied.
    public let summary: String

    public init(id: String, name: String, summary: String) {
        self.id = id
        self.name = name
        self.summary = summary
    }
}

public extension AIModel {
    /// The models `codex exec --model` accepts, as the installed CLI lists them.
    ///
    /// Names read off `~/.codex/models_cache.json` on 2026-08-11 with codex-cli
    /// 0.147.0 — the CLI has no `models` subcommand and no `--help` text that
    /// enumerates them, so that cache is the only place the list exists. It is
    /// the CLI's private file and it gets refreshed behind us, which is why this
    /// list is copied rather than read: a format change there would break every
    /// reply, and a stale name here only costs a picker row.
    ///
    /// Every id below was then *run*, once each, through the same locked-down
    /// invocation a reply uses — flags, schema, prompt on stdin — and each wrote
    /// a schema-valid answer back. A name in that cache is not evidence it
    /// works: `--model not-a-real-model-xyz` is accepted by the CLI without
    /// complaint and fails only at the API, with
    /// `400 invalid_request_error`, so an unverified id would ship as a picker
    /// row that breaks every reply the moment somebody chose it.
    ///
    /// Absent on purpose:
    ///
    /// - `gpt-5.4` and `gpt-5.4-mini`. Both ran, and the cache marks both for
    ///   deprecation and redirects them to `gpt-5.6-terra` and `gpt-5.6-luna`.
    ///   Offering a choice the provider has announced the end of buys the user a
    ///   reply that stops working on a date nobody told them.
    /// - `gpt-5.6-sol-wm` and `codex-auto-review`, which the cache hides. The
    ///   first is a Work Mode routing alias the cache marks unsupported over the
    ///   API — it ran anyway, which is the sort of thing hidden means — and the
    ///   second is the model Codex reviews its own commands with.
    ///
    /// An id that has left this list does not disappear from the screen — see
    /// `named(_:)`.
    static let catalog: [AIModel] = [
        AIModel(
            id: "gpt-5.6-sol",
            name: "GPT-5.6 Sol",
            summary: "가장 좋은 모델입니다. 느리고 사용량을 많이 씁니다."
        ),
        AIModel(
            id: "gpt-5.6-terra",
            name: "GPT-5.6 Terra",
            summary: "속도와 품질이 균형 잡힌 모델입니다."
        ),
        AIModel(
            id: "gpt-5.6-luna",
            name: "GPT-5.6 Luna",
            summary: "가장 빠르고 싼 모델입니다."
        ),
        AIModel(
            id: "gpt-5.5",
            name: "GPT-5.5",
            summary: "이전 세대의 가장 좋은 모델입니다."
        )
    ]

    /// The catalog entry for an id, or one that names itself.
    ///
    /// A stored id can outlive the list — the provider retires a name, or the
    /// user downgrades TalkFlow after picking something newer. Dropping it would
    /// change which model answers without saying so, and leaving the picker with
    /// nothing selected would have the screen show a blank where the user's own
    /// choice is. So an unrecognised id becomes an option whose name is the id,
    /// which is the one thing about it that is certainly true.
    static func named(_ id: String) -> AIModel {
        catalog.first { $0.id == id }
            ?? AIModel(
                id: id,
                name: id,
                summary: "이 버전의 TalkFlow가 아는 목록에는 없는 모델입니다."
            )
    }
}

/// Which model TalkFlow asks for, including the answer "don't ask".
///
/// `codexDefault` is the default and passes no `-m` at all, so the model is
/// whatever `~/.codex/config.toml` says — which is what every install did before
/// this setting existed. Nobody's replies change by upgrading.
///
/// The cost of that default is worth naming where the setting is: the file it
/// defers to belongs to Codex CLI and not to TalkFlow, so editing it for some
/// unrelated project quietly changes what answers in KakaoTalk.
public enum AIModelChoice: Hashable, Sendable {
    case codexDefault
    case pinned(AIModel)

    /// The value `-m` should be given, or nil when the flag must be left off.
    /// Also what gets stored: the choice is one nullable column, not a column
    /// plus a flag that could disagree with it.
    public var modelID: String? {
        switch self {
        case .codexDefault: nil
        case let .pinned(model): model.id
        }
    }

    /// Blank reads as unchosen, not as a model with an empty name. A column that
    /// once held `''` — an older write, a hand-edited row — would otherwise send
    /// `-m ''` and fail every call.
    public init(modelID: String?) {
        guard let modelID, !modelID.trimmingCharacters(in: .whitespaces).isEmpty else {
            self = .codexDefault
            return
        }
        self = .pinned(.named(modelID))
    }
}
