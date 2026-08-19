import SwiftUI

/// 저장 and 취소 for the drafted part of the settings form.
///
/// The screen used to show only failures, so a save that worked looked exactly
/// like a save that never happened. All three states are reported here: pending
/// edits, the write itself, and the result.
struct SettingsSaveBar: View {
    private let status: SettingsModel.SaveStatus
    private let hasUnsavedChanges: Bool
    private let canSave: Bool
    private let onSave: () -> Void
    private let onCancel: () -> Void

    init(
        status: SettingsModel.SaveStatus,
        hasUnsavedChanges: Bool,
        canSave: Bool,
        onSave: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.status = status
        self.hasUnsavedChanges = hasUnsavedChanges
        self.canSave = canSave
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        Section {
            HStack {
                statusLabel
                Spacer()
                Button("취소", action: onCancel)
                    .disabled(!hasUnsavedChanges)
                    .help("마지막으로 저장한 값으로 되돌립니다")
                Button("저장", action: onSave)
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!canSave)
                    .help("바꾼 말투와 키워드를 저장합니다")
            }
            Text("말투와 키워드는 저장을 눌러야 적용됩니다. 아래 스위치는 누르는 즉시 적용됩니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch status {
        case .saving:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("저장하는 중입니다.")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        case let .failed(message):
            Label("저장하지 못했습니다. \(message)", systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.orange)
        case .idle, .saved:
            // A finished save is only worth reporting while the draft still
            // matches what went to disk.
            if hasUnsavedChanges {
                Text("저장하지 않은 변경이 있습니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if status == .saved {
                Label("저장했습니다.", systemImage: "checkmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.green)
            }
        }
    }
}
