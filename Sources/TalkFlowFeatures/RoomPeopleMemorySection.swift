import SwiftUI
import TalkFlowApplication
import TalkFlowDomain

/// 사람 기억, directly under 대화 기억 and deliberately not inside it.
///
/// The two are siblings: one is what this room is, the other is who is in it,
/// and both are background the model gets before it reads a message. Under the
/// same heading they would read as one setting with a sub-option, and the
/// sub-option would inherit the parent's default — which is on, in every room.
/// That is exactly the inheritance this feature must not have.
///
/// So: its own section, its own switch, off. A room already remembering its
/// conversation is not a room that agreed to keep files on the people in it, and
/// the difference is the whole reason this is a separate line on the screen.
///
/// There is nothing to edit here. The notes belong to people rather than to
/// rooms, so they are read and corrected on the 사람 tab; what a room decides is
/// only whether it takes part.
struct RoomPeopleMemorySection: View {
    private let entry: ChatRoomPolicy
    private let onChange: (RoomPolicy) -> Void

    init(entry: ChatRoomPolicy, onChange: @escaping (RoomPolicy) -> Void) {
        self.entry = entry
        self.onChange = onChange
    }

    var body: some View {
        Section {
            Toggle("이 방의 사람 기억", isOn: remembers)
                .disabled(!answers)

            Text(note)
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            SettingHelpLabel("사람 기억", help: .remembersPeople)
        }
    }

    private var answers: Bool {
        entry.policy.responseMode != .off && entry.policy.responseMode != .detectOnly
    }

    private var remembers: Binding<Bool> {
        Binding(
            get: { entry.policy.remembersPeople },
            set: { on in
                var updated = entry.policy
                updated.remembersPeople = on
                onChange(updated)
            }
        )
    }

    /// What this room does now. The general explanation is behind the `?`; what
    /// belongs here is the consequence a person is agreeing to as they flip it,
    /// said in the terms of this room.
    private var note: String {
        guard answers else {
            return "응답 모드가 \"\(entry.policy.responseMode.title)\"이라 사람 기억도 동작하지 않습니다."
        }
        guard entry.policy.remembersPeople else {
            return "이 방 사람들에 대해 아무것도 적어 두지 않습니다."
        }
        return """
        이 방에서 \(PersonNote.replyThreshold)번 이상 답장을 받은 사람에 대해 \
        \(PersonNote.characterLimit)자짜리 메모를 적어 두고, 그 사람이 이 방에서 말하면 그 메모를 답장 요청에 함께 보냅니다. \
        메모는 \"사람\" 탭에서 읽고 고치고 지울 수 있습니다. \
        AI 호출은 늘지 않습니다 — 대화 기억을 갱신할 때 같이 씁니다.
        """
    }
}
