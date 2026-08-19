import Foundation

public struct ChatMember: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let profileImageURL: URL?

    public init(id: String, displayName: String, profileImageURL: URL? = nil) {
        self.id = id
        self.displayName = displayName
        self.profileImageURL = profileImageURL
    }
}
