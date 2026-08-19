import Foundation

public struct AccountProfile: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let label: String
    public let fingerprint: String
    /// The name KakaoTalk shows for this account, as it appears on the messages
    /// it sent. Nil while it is unknown — a fresh sign-in that has not written
    /// anything yet leaves no name to read, and guessing one would have the app
    /// answer to somebody else's.
    public let nickname: String?

    public init(
        id: UUID = UUID(),
        label: String,
        fingerprint: String,
        nickname: String? = nil
    ) {
        self.id = id
        self.label = label
        self.fingerprint = fingerprint
        self.nickname = nickname
    }

    /// The same account, now that its KakaoTalk name is known. Keeps `id` so
    /// learning the name does not read as a different account arriving.
    public func named(_ nickname: String?) -> AccountProfile {
        AccountProfile(id: id, label: label, fingerprint: fingerprint, nickname: nickname)
    }
}
