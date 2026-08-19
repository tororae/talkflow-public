import TalkFlowDomain

public struct LoadChatRooms: Sendable {
    private let connection: any KakaoConnection

    public init(connection: any KakaoConnection) {
        self.connection = connection
    }

    /// Direct rooms and group rooms are listed separately in the UI, so ordering
    /// happens once here instead of in every screen that shows a room list.
    public func callAsFunction() async throws -> [ChatRoom] {
        try await connection.chatRooms()
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }
}
