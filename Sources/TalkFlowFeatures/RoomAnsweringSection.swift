import SwiftUI
import TalkFlowApplication
import TalkFlowDomain

/// 언제 답하나 — the four settings that decide whether a message gets an answer
/// at all, in the order the pipeline asks them.
///
/// Together rather than scattered because they compose: the mode says who may be
/// answered, the call signs say what counts as being addressed, and the condition
/// says what is worth answering. Read apart, each looks like the whole rule and
/// none of them is.
///
/// 답변 활성화 시간 used to be the fourth and has moved to 「언제 자리에 있나」. It
/// answers a different question from these three — not which messages deserve an
/// answer but when this account is around at all — and it belongs with the two
/// other settings that answer that one.
struct RoomAnsweringSection: View {
    let entry: ChatRoomPolicy
    let model: ChatRoomListModel
    let onChange: (RoomPolicy) -> Void

    var body: some View {
        Section {
            SettingHelpRow("응답 모드", help: .responseMode) {
                Picker("응답 모드", selection: binding(\.responseMode)) {
                    ForEach(ResponseMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
            }
        } header: {
            Text("언제 답하나")
        } footer: {
            Text("응답 모드가 누구에게 답할지를 정하고, 아래 두 가지가 차례로 그것을 좁힙니다. 언제 답하는지는 \"답변 활성화 시간\"에서 정합니다.")
        }

        RoomCallSignSection(
            signs: model.callSigns(for: entry),
            recentCalls: model.recentCalls,
            issue: model.keywordIssue,
            readFromThisRoom: model.readNicknameFromThisRoom,
            answersReplies: binding(\.answersReplies),
            onAdd: { model.addKeyword($0, to: entry) },
            onRemove: { model.removeKeyword($0, from: entry) },
            onRereadNickname: { await model.rereadNickname(for: entry) }
        )

        RoomAnsweringConditionSection(
            entry: entry,
            globalCondition: model.globalCondition,
            issue: model.conditionIssue
        ) { condition in
            model.setAnsweringCondition(condition, for: entry)
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<RoomPolicy, Value>) -> Binding<Value> {
        Binding(
            get: { entry.policy[keyPath: keyPath] },
            set: { newValue in
                var updated = entry.policy
                updated[keyPath: keyPath] = newValue
                onChange(updated)
            }
        )
    }
}
