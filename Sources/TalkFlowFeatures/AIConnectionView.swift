import SwiftUI
import TalkFlowDomain

public struct AIConnectionView: View {
    @Bindable private var model: AIConnectionModel
    @State private var isConfirmingSignOut = false

    public init(model: AIConnectionModel) {
        self.model = model
    }

    public var body: some View {
        GroupBox("AI 답변 연결") {
            VStack(alignment: .leading, spacing: 10) {
                Text(message)
                    .foregroundStyle(.secondary)

                switch model.status {
                case .connected:
                    HStack(spacing: 8) {
                        Button("다른 계정으로 로그인") {
                            Task { await model.reconnect() }
                        }
                        Button("연동 해제") { isConfirmingSignOut = true }
                    }
                    .disabled(model.isBusy)
                case .needsLogin, .unavailable:
                    connectButton
                case .checking:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await model.refresh() }
        // Asked before, not undone after. Nothing here can put the credential
        // back — the user has to go and log in again — and while it is gone no
        // room gets an answer.
        .confirmationDialog(
            "Codex 연동을 해제할까요?",
            isPresented: $isConfirmingSignOut,
            titleVisibility: .visible
        ) {
            Button("연동 해제", role: .destructive) {
                Task { await model.disconnect() }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text(
                """
                해제하면 다시 로그인할 때까지 답장을 만들 수 없습니다.
                자격 증명은 Codex CLI가 이 기기에 저장해 둔 것 하나뿐이라, 터미널에서 쓰는 codex도 함께 로그아웃됩니다.
                """
            )
        }
    }

    private var connectButton: some View {
        Button(model.activity == .connecting ? "브라우저 로그인 확인 중…" : "Codex로 로그인") {
            Task { await model.connect() }
        }
        .disabled(model.isBusy)
    }

    private var message: String {
        switch model.activity {
        case .connecting:
            return "브라우저에서 로그인을 마치면 연결됩니다."
        case .disconnecting:
            return "연동을 해제하는 중입니다."
        case .none:
            break
        }

        switch model.status {
        case .checking:
            return "Codex 연결 상태를 확인하는 중입니다."
        case .needsLogin:
            return "ChatGPT 계정으로 로그인하면 이 기기의 Codex CLI가 답변을 생성합니다."
        case let .connected(method):
            return method == .chatGPT
                ? "ChatGPT 계정으로 Codex가 연결되었습니다."
                : "사용자 API 키로 Codex가 연결되었습니다."
        case let .unavailable(reason):
            return reason
        }
    }
}
