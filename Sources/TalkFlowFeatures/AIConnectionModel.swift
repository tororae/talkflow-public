import Observation
import TalkFlowDomain

@MainActor
@Observable
public final class AIConnectionModel {
    /// What the model is in the middle of, rather than one flag per button.
    ///
    /// Every one of these takes the same account away from underneath the
    /// others, so they have to exclude each other rather than merely each say
    /// whether they are running. Two booleans would allow a 연동 해제 to start
    /// while a login is still waiting on a browser.
    public enum Activity: Equatable, Sendable {
        case connecting
        case disconnecting
    }

    public private(set) var status: AIConnectionStatus = .checking
    public private(set) var activity: Activity?
    private let connection: any AIProviderConnection

    public var isBusy: Bool { activity != nil }

    public init(connection: any AIProviderConnection) {
        self.connection = connection
    }

    public func refresh() async {
        status = await connection.status()
    }

    public func connect() async {
        await run(.connecting) { await $0.beginLogin() }
    }

    /// Signing out and then straight back in, which is the only way to land on a
    /// different account: `codex login` on a machine that already holds a
    /// credential has nothing to ask about.
    ///
    /// The sign-out half is not treated as a step that can be skipped when it
    /// fails. A login started against a credential that is still there returns
    /// the account the user was trying to leave, and the screen would then
    /// report success for the opposite of what they asked.
    public func reconnect() async {
        await run(.connecting) { connection in
            let signedOut = await connection.signOut()
            guard signedOut == .needsLogin else { return signedOut }
            return await connection.beginLogin()
        }
    }

    public func disconnect() async {
        await run(.disconnecting) { await $0.signOut() }
    }

    /// One at a time, and the flag is cleared however the work ends.
    private func run(
        _ activity: Activity,
        _ work: (any AIProviderConnection) async -> AIConnectionStatus
    ) async {
        guard self.activity == nil else { return }
        self.activity = activity
        defer { self.activity = nil }
        status = await work(connection)
    }
}
