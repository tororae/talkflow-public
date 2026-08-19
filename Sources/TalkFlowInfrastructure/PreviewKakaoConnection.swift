import Foundation
import TalkFlowDomain

public struct PreviewKakaoConnection: KakaoConnection {
    public init() {}

    public func status() async -> KakaoConnectionStatus {
        .unavailable(reason: "카카오톡 연결 검증은 아직 시작하지 않았습니다.")
    }

    public func chatRooms() async throws -> [ChatRoom] {
        []
    }

    public func recentMessages(in chatRoom: ChatRoom, limit: Int) async throws -> [ChatMessage] {
        []
    }
}
