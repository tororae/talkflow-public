public enum AIConnectionStatus: Equatable, Sendable {
    public enum AuthenticationMethod: String, Equatable, Sendable {
        case chatGPT
        case apiKey
    }

    case checking
    case needsLogin
    case connected(method: AuthenticationMethod)
    case unavailable(reason: String)
}

public protocol AIProviderConnection: Sendable {
    func status() async -> AIConnectionStatus
    func beginLogin() async -> AIConnectionStatus
    /// Hands the account back. Nothing can be drafted afterwards until somebody
    /// logs in again, which is the point: it is how a user takes their ChatGPT
    /// account off a machine TalkFlow is running on, and how they get to the
    /// login screen when they want a different one.
    func signOut() async -> AIConnectionStatus
}
