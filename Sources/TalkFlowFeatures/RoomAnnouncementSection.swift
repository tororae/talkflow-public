import SwiftUI
import TalkFlowApplication
import TalkFlowDomain

/// 자리 알림 — the line said on the way in and on the way out.
///
/// Under 「내보내기」, beside 먼저 말 걸기: both are the app speaking unprompted, and
/// this one reports a change in when the account is around — 집중 시간이 서고 지고,
/// 답변 활성화 시간이 열리고 닫히는 네 순간. The occasions name a presence that is
/// set two groups up, but the setting itself is an outgoing message, so it lives
/// with the other thing the app sends on its own.
///
/// Four checkboxes rather than four features. From inside the room the four
/// transitions are two events — this account starts answering, this account stops
/// — and the wording is one prompt, so the screen shows them as one setting with
/// four occasions.
///
/// The separate switch is the point of it being a row rather than a consequence:
/// turning 집중 시간 on does not turn speaking on. One is a pace, the other is the
/// app putting words into a room nobody asked it to speak in.
struct RoomAnnouncementSection: View {
    private let entry: ChatRoomPolicy
    private let onChange: (RoomPolicy) -> Void

    init(entry: ChatRoomPolicy, onChange: @escaping (RoomPolicy) -> Void) {
        self.entry = entry
        self.onChange = onChange
    }

    private var announcements: StateAnnouncements { entry.policy.announcements }

    var body: some View {
        Section {
            SettingHelpRow("자리 알림", help: .burningAnnouncement) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Self.occasions, id: \.transition) { occasion in
                        Toggle(occasion.title, isOn: binding(for: occasion.transition))
                            .disabled(!answers || !isRelevant(occasion.transition))
                    }
                }
            }

            if announcements.isOn {
                LabeledContent("최근 대화가 있었을 때만") {
                    DurationField(
                        seedID: "\(entry.id)-announce-window",
                        seconds: announcements.withinRecentConversation,
                        presets: Self.windowPresets,
                        isEnabled: true
                    ) { seconds in
                        var updated = entry.policy
                        updated.announcements.withinRecentConversation = seconds
                        onChange(updated)
                    }
                }

                LabeledContent("전송") {
                    Picker("전송", selection: delivery) {
                        ForEach(AnnouncementDelivery.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                }
            }
        } header: {
            Text("자리 알림")
        } footer: {
            Text(note)
        }
    }

    private var answers: Bool {
        entry.policy.responseMode != .off && entry.policy.responseMode != .detectOnly
    }

    /// A transition that cannot happen in this room is not offered. 집중 시간 off
    /// means no burn to announce, and unlimited hours never open or close — a
    /// checkbox for either would be a switch with nothing behind it, which is
    /// what 감지 전용 already taught this screen not to ship.
    private func isRelevant(_ transition: StateAnnouncement) -> Bool {
        switch transition {
        case .burningStarted, .burningEnded:
            entry.policy.burning.isEnabled
        case .activeHoursOpened, .activeHoursClosed:
            entry.policy.activeHours.isLimited
        }
    }

    private func binding(for transition: StateAnnouncement) -> Binding<Bool> {
        Binding(
            get: { announcements.announces(transition) },
            set: { isOn in
                var updated = entry.policy
                if isOn {
                    updated.announcements.transitions.insert(transition)
                } else {
                    updated.announcements.transitions.remove(transition)
                }
                onChange(updated)
            }
        )
    }

    private var delivery: Binding<AnnouncementDelivery> {
        Binding(
            get: { announcements.delivery },
            set: { value in
                var updated = entry.policy
                updated.announcements.delivery = value
                onChange(updated)
            }
        )
    }

    /// Says what this room does now, and — where it applies — why a box is greyed
    /// out. The general explanation is behind the `?`.
    private var note: String {
        guard answers else {
            return "응답 모드가 \"\(entry.policy.responseMode.title)\"이라 알림도 나가지 않습니다."
        }
        guard announcements.isOn else {
            return "아무것도 알리지 않습니다. 집중 시간이나 답변 활성화 시간이 바뀌어도 조용히 바뀝니다."
        }
        guard announcements.delivery == .delivers else {
            return "만들기만 하고 보내지 않습니다. 활동 화면에서 사람이 눌러야 나갑니다. 문구는 그때그때 대화를 보고 AI가 씁니다."
        }
        guard entry.policy.deliveryMode.deliversAutomatically else {
            return "전송 방식이 \"\(entry.policy.deliveryMode.title)\"이라 지금은 만들기만 합니다. 사람이 눌러야 나갑니다."
        }
        return "사람 확인 없이 나갑니다. 문구는 그때그때 대화를 보고 AI가 쓰고, 할 말이 없으면 아무것도 보내지 않습니다."
    }

    private static let occasions: [(transition: StateAnnouncement, title: String)] = [
        (.burningStarted, "집중 시간이 시작될 때"),
        (.burningEnded, "집중 시간이 끝날 때"),
        (.activeHoursOpened, "답변 시간이 시작될 때"),
        (.activeHoursClosed, "답변 시간이 끝날 때")
    ]

    private static let windowPresets: [TimeInterval] = [300, 600, 1_800, 3_600]
}
