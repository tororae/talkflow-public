import SwiftUI

struct SyncActivityView: View {
    private let model: SyncActivityModel

    init(model: SyncActivityModel) {
        self.model = model
    }

    var body: some View {
        GroupBox("대화 감지") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(state.title, systemImage: state.symbol)
                        .foregroundStyle(state.tint)

                    Spacer()

                    Button(model.isObserving ? "감지 중지" : "감지 시작") {
                        if model.isObserving {
                            model.stopObserving()
                        } else {
                            model.startObserving()
                        }
                    }
                }

                // Not secondary while stalled. The whole failure is that this
                // line said something reassuring in grey while nothing worked.
                Text(model.statusText)
                    .foregroundStyle(model.isStalled ? .primary : .secondary)

                if let report = model.lastReport {
                    Text("아카이브 \(report.totalMessages)건 · 직전 반영 추가 \(report.insertedMessages) / 수정 \(report.updatedMessages)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Three states, not two. Running and running-but-deaf were the same green
    /// light, and that is how the app sat blind for hours looking healthy.
    private var state: (title: String, symbol: String, tint: Color) {
        if model.isStalled {
            return ("응답 없음", "exclamationmark.triangle.fill", .orange)
        }
        if model.isObserving {
            return ("감지 중", "dot.radiowaves.left.and.right", .green)
        }
        return ("멈춤", "pause.circle", .secondary)
    }
}
