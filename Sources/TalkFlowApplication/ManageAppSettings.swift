import TalkFlowDomain

/// The settings screen and the global pause switch both read and write the same
/// row, so they share one use case rather than each holding a store.
public struct ManageAppSettings: Sendable {
    private let store: any AppSettingsStore

    public init(store: any AppSettingsStore) {
        self.store = store
    }

    public func responseStyle() async throws -> ResponseStyle {
        try await store.responseStyle()
    }

    public func save(_ style: ResponseStyle) async throws {
        try await store.save(style)
    }

    public func answeringCondition() async throws -> AnsweringCondition {
        try await store.answeringCondition()
    }

    public func save(_ condition: AnsweringCondition) async throws {
        try await store.save(condition)
    }

    public func globalResponsesEnabled() async throws -> Bool {
        try await store.globalResponsesEnabled()
    }

    public func setGlobalResponsesEnabled(_ enabled: Bool) async throws {
        try await store.setGlobalResponsesEnabled(enabled)
    }

    public func launchesAtLogin() async throws -> Bool {
        try await store.launchesAtLogin()
    }

    public func setLaunchesAtLogin(_ enabled: Bool) async throws {
        try await store.setLaunchesAtLogin(enabled)
    }

    public func sendUsePolicyAccepted() async throws -> Bool {
        try await store.sendUsePolicyAccepted()
    }

    public func setSendUsePolicyAccepted(_ accepted: Bool) async throws {
        try await store.setSendUsePolicyAccepted(accepted)
    }

    public func wakesDisplayToSend() async throws -> Bool {
        try await store.wakesDisplayToSend()
    }

    public func setWakesDisplayToSend(_ enabled: Bool) async throws {
        try await store.setWakesDisplayToSend(enabled)
    }

    public func aiModel() async throws -> AIModelChoice {
        try await store.aiModel()
    }

    public func setAIModel(_ choice: AIModelChoice) async throws {
        try await store.setAIModel(choice)
    }
}
