import SwiftUI
import TalkFlowDomain

struct SendQueueView: View {
    private let model: SendQueueModel
    private let usePolicyAccepted: Bool

    init(model: SendQueueModel, usePolicyAccepted: Bool) {
        self.model = model
        self.usePolicyAccepted = usePolicyAccepted
    }

    var body: some View {
        GroupBox("전송 대기열") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(
                        model.isRunning ? "확인 중" : "멈춤",
                        systemImage: model.isRunning ? "paperplane" : "pause.circle"
                    )
                    .foregroundStyle(model.isRunning ? .green : .secondary)
                    Spacer()
                    Text(model.summary).foregroundStyle(.secondary)
                }

                if !usePolicyAccepted {
                    Label(
                        "설정에서 전송 이용 정책에 동의하기 전에는 아무것도 전송되지 않습니다.",
                        systemImage: "exclamationmark.shield"
                    )
                    .foregroundStyle(.orange)
                    .font(.footnote)
                }

                ForEach(model.waiting.prefix(3)) { send in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "clock")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(send.chatRoomName.isEmpty ? send.chatRoomID : send.chatRoomName)
                                .fontWeight(.medium)
                            Text(send.text)
                                .lineLimit(2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.footnote)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
