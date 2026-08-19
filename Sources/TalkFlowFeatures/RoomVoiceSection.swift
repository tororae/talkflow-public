import SwiftUI
import TalkFlowApplication
import TalkFlowDomain

/// 어떻게 말하나 — everything that shapes the reply once the room has decided to
/// make one.
///
/// 사진 함께 읽기 looks like plumbing and is not: it sends pictures out of the
/// conversation to the provider. It belongs beside the wording rather than in a
/// list of toggles, because the question it answers is the same one — what goes
/// into the message and what the model gets to see.
struct RoomVoiceSection: View {
    let entry: ChatRoomPolicy
    let model: ChatRoomListModel
    let summaryModel: RoomSummaryModel
    let onChange: (RoomPolicy) -> Void

    var body: some View {
        RoomResponseStyleSection(
            entry: entry,
            globalStyle: model.globalStyle
        ) { style in
            var updated = entry.policy
            updated.responseStyleOverride = style
            onChange(updated)
        }

        Section {
            SettingHelpRow("사진 함께 읽기", help: .readsPhotos) {
                Toggle("사진 함께 읽기", isOn: binding(\.readsPhotos))
                    .labelsHidden()
            }
            SettingHelpRow("웹 검색", help: .webSearch) {
                Toggle("웹 검색", isOn: binding(\.webSearch))
                    .labelsHidden()
            }
            SettingHelpRow("링크 읽기", help: .readsLinks) {
                Toggle("링크 읽기", isOn: binding(\.readsLinks))
                    .labelsHidden()
            }
        } header: {
            Text("무엇을 담나")
        } footer: {
            Text("사진·웹 검색·링크 읽기는 이 방의 내용을 이 Mac 밖으로 내보내는 설정입니다.")
        }

        RoomConversationSummarySection(
            entry: entry,
            model: summaryModel,
            onChange: onChange
        )

        // A sibling of 대화 기억, not a child of it. Nested, it would inherit that
        // switch's default — on, in every room — which is the one inheritance
        // this must not have.
        RoomPeopleMemorySection(entry: entry, onChange: onChange)
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

/// 내보내기 — 이 방에서 밖으로 나가는 것들. 답장의 전송 방식(초안만·자동·상시)과,
/// 아무도 부르지 않았는데 앱이 스스로 거는 두 말 — 먼저 말 걸기와 자리 알림.
///
/// 스스로 거는 말 둘을 여기 나란히 두는 이유: 둘 다 부르지 않은 대화에 앱이 끼어드는
/// 유일한 행동이고, 둘 다 초안·전송 스위치를 따로 가지며, 둘 다 위의 전송 방식이
/// 자동으로 나갈지를 최종적으로 정한다. 성격도 게이트도 같은 것을 흩어 두지 않는다.
struct RoomDeliverySection: View {
    let entry: ChatRoomPolicy
    let onChange: (RoomPolicy) -> Void

    var body: some View {
        Section {
            SettingHelpRow("전송 방식", help: .deliveryMode) {
                Picker("전송 방식", selection: binding(\.deliveryMode)) {
                    ForEach(DeliveryMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
            }
        } header: {
            Text("내보내기")
        } footer: {
            Text(entry.policy.deliveryMode.deliversAutomatically
                 ? "이 방은 사람 확인 없이 답장을 보냅니다."
                 : "초안만 만들고, 활동 탭에서 확인한 뒤에 보냅니다.")
        }

        RoomConversationOpenerSection(entry: entry, onChange: onChange)

        RoomAnnouncementSection(entry: entry, onChange: onChange)
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
