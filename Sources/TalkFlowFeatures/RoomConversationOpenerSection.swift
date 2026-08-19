import SwiftUI
import TalkFlowApplication
import TalkFlowDomain

/// 먼저 말 걸기 and the cadence it uses — one of the two unprompted-speech
/// settings under 「내보내기」, beside 자리 알림.
///
/// It sits with 자리 알림 rather than among the reply settings because the two are
/// the same kind of thing: everything else on the form decides what happens to a
/// message somebody sent, while these two decide whether TalkFlow says anything at
/// all when nobody did. 자리 알림 reports a coming or going; this opens a subject.
/// Different lines, one nature — the app speaking on its own — so they share a home.
struct RoomConversationOpenerSection: View {
    private let entry: ChatRoomPolicy
    private let onChange: (RoomPolicy) -> Void

    init(entry: ChatRoomPolicy, onChange: @escaping (RoomPolicy) -> Void) {
        self.entry = entry
        self.onChange = onChange
    }

    var body: some View {
        Section("먼저 말 걸기") {
            SettingHelpRow("먼저 말 걸기", help: .conversationOpener) {
                Picker("먼저 말 걸기", selection: opener) {
                    ForEach(ConversationOpener.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                // A room the user switched off is a room that says nothing, and
                // this is not the setting that gets to reopen it.
                .disabled(!answers)
            }

            IntervalRangeFields(
                seedID: entry.id,
                interval: entry.policy.conversationOpenerInterval,
                input: .conversationOpener,
                isEnabled: entry.policy.conversationOpener.isOn
            ) { parsed in
                guard parsed != entry.policy.conversationOpenerInterval else { return }
                var updated = entry.policy
                updated.conversationOpenerInterval = parsed
                onChange(updated)
            }

            if entry.policy.conversationOpener.isOn {
                Toggle("내가 마지막에 답했어도 먼저 말 걸기", isOn: repeatEnabled)
                if entry.policy.openerRepeatLimit > 0 {
                    Stepper(
                        "답이 없어도 연속 \(entry.policy.openerRepeatLimit)번까지",
                        value: repeatLimit,
                        in: 1 ... 10
                    )
                    Picker("다시 말 걸 때", selection: repeatTopic) {
                        ForEach(OpenerRepeatTopic.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Toggle("활성 시간 밖에선 주기 멈춤", isOn: cadencePauses)
                }
                TextField("참고할 지시 (비우면 관련 말 안 함)", text: hint, axis: .vertical)
                    .lineLimit(1 ... 3)
                    .multilineTextAlignment(.leading)
            }

            if let note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        if entry.policy.conversationOpener.isOn {
            RoomActiveHoursSection(
                title: "먼저 말 걸기 시간",
                rowLabel: "말 거는 시간",
                hours: entry.policy.conversationOpenerHours
            ) { hours in
                var updated = entry.policy
                updated.conversationOpenerHours = hours
                onChange(updated)
            }
        }
    }

    private var answers: Bool {
        entry.policy.responseMode != .off && entry.policy.responseMode != .detectOnly
    }

    private var opener: Binding<ConversationOpener> {
        Binding(
            get: { entry.policy.conversationOpener },
            set: { value in
                var updated = entry.policy
                updated.conversationOpener = value
                onChange(updated)
            }
        )
    }

    /// The checkbox turns the run on and off; the stepper sets its length. Off is
    /// zero, on restores at least one, so ticking the box never lands on a limit
    /// of zero that reads as on but never fires.
    private var repeatEnabled: Binding<Bool> {
        Binding(
            get: { entry.policy.openerRepeatLimit > 0 },
            set: { on in
                var updated = entry.policy
                updated.openerRepeatLimit = on ? max(1, updated.openerRepeatLimit) : 0
                onChange(updated)
            }
        )
    }

    private var repeatLimit: Binding<Int> {
        Binding(
            get: { entry.policy.openerRepeatLimit },
            set: { value in
                var updated = entry.policy
                updated.openerRepeatLimit = value
                onChange(updated)
            }
        )
    }

    private var repeatTopic: Binding<OpenerRepeatTopic> {
        Binding(
            get: { entry.policy.openerRepeatTopic },
            set: { value in
                var updated = entry.policy
                updated.openerRepeatTopic = value
                onChange(updated)
            }
        )
    }

    private var cadencePauses: Binding<Bool> {
        Binding(
            get: { entry.policy.openerCadencePausesOutsideHours },
            set: { value in
                var updated = entry.policy
                updated.openerCadencePausesOutsideHours = value
                onChange(updated)
            }
        )
    }

    /// Empty reads back as no hint at all rather than a blank one — the prompt
    /// leaves the line out entirely when there is nothing to carry.
    private var hint: Binding<String> {
        Binding(
            get: { entry.policy.openerPromptHint ?? "" },
            set: { value in
                var updated = entry.policy
                updated.openerPromptHint = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil
                    : value
                onChange(updated)
            }
        )
    }

    /// Two sentences only, and never what the room does in general — that belongs
    /// to `RoomBehaviourSummary`, which reads the whole form at once. What has to
    /// be here is why the picker is greyed out, and which of the two consents was
    /// just given: agreeing that TalkFlow may answer for you is not agreeing that
    /// it may speak for you, and a screen that leaves that to a `?` leaves it to
    /// somebody who has already decided.
    private var note: String? {
        guard answers else {
            return "응답 모드가 \"\(entry.policy.responseMode.title)\"이라 먼저 말을 걸지 않습니다."
        }
        guard entry.policy.conversationOpener.isOn else { return nil }
        return delivery
    }

    private var delivery: String {
        guard entry.policy.conversationOpener == .delivers else {
            return "만들기만 하고 보내지 않습니다. 활동 화면에서 사람이 눌러야 나갑니다."
        }
        guard entry.policy.deliveryMode.deliversAutomatically else {
            return "전송 방식이 \"\(entry.policy.deliveryMode.title)\"이라 지금은 만들기만 합니다. 사람이 눌러야 나갑니다."
        }
        return "만든 말이 사람 확인 없이 \"\(entry.policy.deliveryMode.title)\"으로 나갑니다."
    }
}
