import SwiftUI
import TalkFlowApplication
import TalkFlowDomain

public struct ConnectionStatusView: View {
    @State private var status: KakaoConnectionStatus = .disconnected
    private let loadStatus: LoadConnectionStatus

    public init(loadStatus: LoadConnectionStatus) {
        self.loadStatus = loadStatus
    }

    public var body: some View {
        ContentUnavailableView(
            "TalkFlow",
            systemImage: "bubble.left.and.bubble.right",
            description: Text(description)
        )
        .task {
            status = await loadStatus()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var description: String {
        switch status {
        case .disconnected:
            "카카오톡 연결을 확인하는 중입니다."
        case let .unavailable(reason):
            reason
        case let .connected(account):
            "\(account.label) 계정이 연결되었습니다."
        }
    }
}
