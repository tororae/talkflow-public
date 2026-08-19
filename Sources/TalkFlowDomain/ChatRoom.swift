import Foundation

public struct ChatRoom: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable {
        case direct
        case group
    }

    public let id: String
    public let displayName: String
    public let kind: Kind

    public init(id: String, displayName: String, kind: Kind) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
    }
}
