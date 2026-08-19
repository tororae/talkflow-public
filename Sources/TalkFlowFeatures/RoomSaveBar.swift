import SwiftUI

/// 저장 and 취소 for one room's settings, and the only thing on the screen that
/// says whether a change took.
///
/// The room screen used to write every control straight to disk and report
/// nothing, which left two questions unanswerable: did that apply, and how do I
/// undo it. Both are answered here — the count says something is pending, 저장
/// commits it, 취소 puts the room back the way it was on disk.
///
/// Deliberately the same shape as `SettingsSaveBar`. Two screens with opposite
/// rules is how neither gets learned.
struct RoomSaveBar: View {
    private let status: ChatRoomListModel.RoomSaveStatus
    private let hasUnsavedChanges: Bool
    private let onSave: () -> Void
    private let onCancel: () -> Void

    init(
        status: ChatRoomListModel.RoomSaveStatus,
        hasUnsavedChanges: Bool,
        onSave: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.status = status
        self.hasUnsavedChanges = hasUnsavedChanges
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        HStack(spacing: 12) {
            statusLabel
            Spacer(minLength: 8)
            Button("취소", action: onCancel)
                .disabled(!hasUnsavedChanges)
                .help("이 방 설정을 마지막으로 저장한 값으로 되돌립니다")
            Button("저장", action: onSave)
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!hasUnsavedChanges)
                .help("바꾼 값을 이 방에 적용합니다")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }

    /// The pending state outranks the last result. Once something is unsaved,
    /// 「저장됨」 from a minute ago is the wrong thing to be reading.
    @ViewBuilder
    private var statusLabel: some View {
        if hasUnsavedChanges {
            Label("저장하지 않은 변경이 있습니다", systemImage: "circle.fill")
                .foregroundStyle(.orange)
                .font(.callout)
                .imageScale(.small)
        } else {
            switch status {
            case .idle:
                Text("이 방에 저장된 설정입니다")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            case .saving:
                Label("저장 중", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            case .saved:
                Label("저장했습니다", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            case let .failed(reason):
                Label(reason, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
                    .lineLimit(2)
            }
        }
    }
}
