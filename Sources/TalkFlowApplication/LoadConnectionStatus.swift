import TalkFlowDomain

public struct LoadConnectionStatus: Sendable {
    private let connection: any KakaoConnection

    public init(connection: any KakaoConnection) {
        self.connection = connection
    }

    public func callAsFunction() async -> KakaoConnectionStatus {
        await connection.status()
    }
}
