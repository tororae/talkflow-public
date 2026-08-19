import Foundation
import GRDB
import TalkFlowDomain

public struct AppSettingsRepository: AppSettingsStore {
    private struct Switches: Sendable {
        var responsesEnabled = false
        var launchesAtLogin = false
        var sendUsePolicyAccepted = false
        var wakesDisplayToSend = true
    }

    private let database: TalkFlowDatabase

    public init(database: TalkFlowDatabase) {
        self.database = database
    }

    public func responseStyle() async throws -> ResponseStyle {
        // Rows are mapped inside the closure because GRDB's `Row` is not Sendable:
        // returning one would force the blocking overload onto an async caller.
        try await database.queue.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM response_style_settings WHERE id = 1") else {
                return ResponseStyle()
            }

            let defaults = ResponseStyle()
            return ResponseStyle(
                tone: row["tone"] as String? ?? defaults.tone,
                length: (row["length"] as String?).flatMap(ResponseStyle.Length.init(rawValue:)) ?? defaults.length,
                emojiUse: (row["emoji_use"] as String?).flatMap(ResponseStyle.EmojiUse.init(rawValue:)) ?? defaults.emojiUse,
                assertiveness: (row["assertiveness"] as String?).flatMap(ResponseStyle.Assertiveness.init(rawValue:)) ?? defaults.assertiveness,
                responseKeywords: KeywordColumn.decode(row["mention_tokens"] as String?)
            )
        }
    }

    public func save(_ style: ResponseStyle) async throws {
        let keywords = KeywordColumn.encode(style.responseKeywords)
        // `mention_tokens` predates the rename to response keywords. The column
        // keeps its name because migrating a table only to relabel it would risk
        // the keywords the user already registered, for nothing.
        try await database.queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO response_style_settings
                    (id, tone, length, emoji_use, assertiveness, mention_tokens)
                VALUES (1, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    tone = excluded.tone,
                    length = excluded.length,
                    emoji_use = excluded.emoji_use,
                    assertiveness = excluded.assertiveness,
                    mention_tokens = excluded.mention_tokens
                """,
                arguments: [
                    style.tone,
                    style.length.rawValue,
                    style.emojiUse.rawValue,
                    style.assertiveness.rawValue,
                    keywords
                ]
            )
        }
    }

    public func answeringCondition() async throws -> AnsweringCondition {
        try await database.queue.read { db in
            AnsweringCondition(
                try String.fetchOne(
                    db,
                    sql: "SELECT answering_condition FROM response_style_settings WHERE id = 1"
                ) ?? ""
            )
        }
    }

    /// Shares the row the style lives in but writes only its own column, and the
    /// style's writer returns the favour. Two writers of one row that each
    /// rewrote the whole thing would have the last one to save quietly undo the
    /// other, and both are edited on the same screen.
    ///
    /// The values in the `VALUES` list are only ever used to create the row, and
    /// they are the same defaults a read of a missing row returns.
    public func save(_ condition: AnsweringCondition) async throws {
        let defaults = ResponseStyle()
        try await database.queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO response_style_settings
                    (id, tone, length, emoji_use, assertiveness, mention_tokens, answering_condition)
                VALUES (1, ?, ?, ?, ?, '[]', ?)
                ON CONFLICT(id) DO UPDATE SET
                    answering_condition = excluded.answering_condition
                """,
                arguments: [
                    defaults.tone,
                    defaults.length.rawValue,
                    defaults.emojiUse.rawValue,
                    defaults.assertiveness.rawValue,
                    condition.text
                ]
            )
        }
    }

    public func globalResponsesEnabled() async throws -> Bool {
        try await switches().responsesEnabled
    }

    public func setGlobalResponsesEnabled(_ enabled: Bool) async throws {
        try await update { $0.responsesEnabled = enabled }
    }

    public func launchesAtLogin() async throws -> Bool {
        try await switches().launchesAtLogin
    }

    public func setLaunchesAtLogin(_ enabled: Bool) async throws {
        try await update { $0.launchesAtLogin = enabled }
    }

    public func sendUsePolicyAccepted() async throws -> Bool {
        try await switches().sendUsePolicyAccepted
    }

    public func setSendUsePolicyAccepted(_ accepted: Bool) async throws {
        try await update { $0.sendUsePolicyAccepted = accepted }
    }

    public func wakesDisplayToSend() async throws -> Bool {
        try await switches().wakesDisplayToSend
    }

    public func setWakesDisplayToSend(_ enabled: Bool) async throws {
        try await update { $0.wakesDisplayToSend = enabled }
    }

    /// A missing row and a null column both read as 선택 안 함, which is correct:
    /// the column arrived null on every machine that upgraded.
    public func aiModel() async throws -> AIModelChoice {
        try await database.queue.read { db in
            AIModelChoice(
                modelID: try String.fetchOne(db, sql: "SELECT ai_model FROM app_settings WHERE id = 1")
            )
        }
    }

    /// Writes its own column only, the way 답변 조건 does in the row above. The
    /// switches share this row and read-modify-write theirs; a writer here that
    /// rewrote the whole thing would undo whichever switch was flipped in
    /// between, and the switches are on the same screen as this picker.
    ///
    /// The values in the `VALUES` list only ever create the row, and they are the
    /// defaults a read of a missing row returns.
    public func setAIModel(_ choice: AIModelChoice) async throws {
        let defaults = Switches()
        try await database.queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO app_settings
                    (id, responses_enabled, launches_at_login,
                     send_use_policy_accepted, wakes_display_to_send, ai_model)
                VALUES (1, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    ai_model = excluded.ai_model
                """,
                arguments: [
                    defaults.responsesEnabled,
                    defaults.launchesAtLogin,
                    defaults.sendUsePolicyAccepted,
                    defaults.wakesDisplayToSend,
                    choice.modelID
                ]
            )
        }
    }

    private func switches() async throws -> Switches {
        try await database.queue.read { db in
            Self.switches(in: try Row.fetchOne(db, sql: "SELECT * FROM app_settings WHERE id = 1"))
        }
    }

    /// The switches share one row, so each writer reads the current set and keeps
    /// the values it is not changing rather than resetting them to defaults.
    private func update(_ change: @Sendable @escaping (inout Switches) -> Void) async throws {
        try await database.queue.write { db in
            var current = Self.switches(in: try Row.fetchOne(db, sql: "SELECT * FROM app_settings WHERE id = 1"))
            change(&current)

            try db.execute(
                sql: """
                INSERT INTO app_settings
                    (id, responses_enabled, launches_at_login,
                     send_use_policy_accepted, wakes_display_to_send)
                VALUES (1, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    responses_enabled = excluded.responses_enabled,
                    launches_at_login = excluded.launches_at_login,
                    send_use_policy_accepted = excluded.send_use_policy_accepted,
                    wakes_display_to_send = excluded.wakes_display_to_send
                """,
                arguments: [
                    current.responsesEnabled,
                    current.launchesAtLogin,
                    current.sendUsePolicyAccepted,
                    current.wakesDisplayToSend
                ]
            )
        }
    }

    private static func switches(in row: Row?) -> Switches {
        Switches(
            responsesEnabled: row?["responses_enabled"] as Bool? ?? false,
            launchesAtLogin: row?["launches_at_login"] as Bool? ?? false,
            sendUsePolicyAccepted: row?["send_use_policy_accepted"] as Bool? ?? false,
            wakesDisplayToSend: row?["wakes_display_to_send"] as Bool? ?? true
        )
    }
}
