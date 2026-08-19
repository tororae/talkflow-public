import SwiftUI
import TalkFlowApplication
import TalkFlowDomain

/// 답변 조건 for one room: follow the one in 설정, or write this room's own.
///
/// A section rather than a row because the choice needs the global text visible
/// beside it. "이 방만 다른 조건" with nothing showing what it would be replacing
/// is a switch the user has to leave the screen to understand.
struct RoomAnsweringConditionSection: View {
    private let entry: ChatRoomPolicy
    private let globalCondition: AnsweringCondition
    private let issue: String?
    /// The typed text, not a built condition: the model does the bounds check,
    /// and a value built here would already be inside the bound.
    private let onChange: (String?) -> Void

    init(
        entry: ChatRoomPolicy,
        globalCondition: AnsweringCondition,
        issue: String?,
        onChange: @escaping (String?) -> Void
    ) {
        self.entry = entry
        self.globalCondition = globalCondition
        self.issue = issue
        self.onChange = onChange
    }

    var body: some View {
        Section {
            // The `?` sits on the section title rather than here. One card
            // explains the whole section, and two buttons opening it would only
            // teach the reader that the second one was not worth pressing.
            Toggle("이 방만 다른 조건 사용", isOn: usesOwn)

            if let own = entry.policy.answeringConditionOverride {
                // Keyed on the room so the text this field holds is put back when
                // another room is opened under it.
                EditableTextField(
                    "예: 일정 잡는 얘기 위주로. 잡담엔 끼지 마.",
                    value: own.text,
                    axis: .vertical,
                    lineLimit: 1...3,
                    onChange: onChange
                )
                .id(entry.id)
                if let issue {
                    Label(issue, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            Text(note)
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            SettingHelpLabel("답변 조건", help: .answeringCondition)
        }
    }

    /// Turning it on copies the global text in rather than starting blank. The
    /// common reason to override is "거의 같은데 이 방만 조금 다르게", and an empty box
    /// makes the user retype what they already wrote once.
    private var usesOwn: Binding<Bool> {
        Binding(
            get: { entry.policy.usesOwnAnsweringCondition },
            set: { on in onChange(on ? globalCondition.text : nil) }
        )
    }

    private var note: String {
        guard entry.policy.usesOwnAnsweringCondition else {
            return globalCondition.isEmpty
                ? "설정의 답변 조건을 따릅니다. 지금은 조건이 없어 AI가 알아서 판단합니다."
                : "설정의 답변 조건을 따릅니다: \(globalCondition.text)"
        }
        return entry.policy.answeringConditionOverride?.isEmpty == true
            ? "이 방은 조건 없이 판단합니다. 설정의 조건도 쓰지 않습니다."
            : "이 방은 위 조건만 씁니다. 설정의 조건은 적용되지 않습니다."
    }
}
