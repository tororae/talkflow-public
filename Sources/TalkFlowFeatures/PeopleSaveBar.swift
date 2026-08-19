import SwiftUI

/// 저장 and 취소 for one person's note, and the only thing on the screen that says
/// whether a change took.
///
/// Deliberately the same shape as `RoomSaveBar`, down to ⌘S and the order of the
/// two buttons. A user who has learned the room screen has learned this one, and
/// three screens with three bargains is how none of them gets learned.
///
/// It carries the refusal as well as the result, which `RoomSaveBar` does not have
/// to. A note over the character limit is not a failed write — nothing was
/// attempted — so without this the user would press 저장 on 320 characters and the
/// screen would answer with silence.
struct PeopleSaveBar: View {
    private let status: PeopleModel.SaveStatus
    private let issue: String?
    private let hasUnsavedChanges: Bool
    private let onSave: () -> Void
    private let onCancel: () -> Void

    init(
        status: PeopleModel.SaveStatus,
        issue: String?,
        hasUnsavedChanges: Bool,
        onSave: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.status = status
        self.issue = issue
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
                .help("이 사람의 메모를 마지막으로 저장한 내용으로 되돌립니다")
            Button("저장", action: onSave)
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!hasUnsavedChanges)
                .help("고친 메모와 링크를 저장합니다")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }

    /// A refusal outranks the pending state, which outranks the last result. Each
    /// one answers the question the one below it would leave open: why 저장 did
    /// nothing, then whether anything is waiting, then whether the last write took.
    @ViewBuilder
    private var statusLabel: some View {
        if let issue {
            Label(issue, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.callout)
                .lineLimit(2)
        } else if hasUnsavedChanges {
            Label("저장하지 않은 변경이 있습니다", systemImage: "circle.fill")
                .foregroundStyle(.orange)
                .font(.callout)
                .imageScale(.small)
        } else {
            switch status {
            case .idle:
                Text("이 사람에 대해 저장된 메모입니다")
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
