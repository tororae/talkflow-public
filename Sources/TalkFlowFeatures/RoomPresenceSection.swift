import SwiftUI
import TalkFlowApplication
import TalkFlowDomain

/// 언제 자리에 있나 — 이 방이 언제 답하는가, 그 하나의 시간표.
///
/// 한때 여기에 집중 시간과 자리 알림도 함께 있었지만 둘 다 옮겨 갔다. 집중 시간은
/// 자기가 덮어쓰는 세 값(끼어들기 확률·최소 응답 간격·판단 주기) 바로 옆,
/// 「얼마나 자주」로 갔다 — 평상값과 그 위에 얹히는 집중값을 한자리에서 읽게 하려고.
/// 자리 알림은 스스로 거는 말이라 「내보내기」에서 먼저 말 걸기와 나란히 둔다. 남은
/// 것은 순수한 시간표 하나뿐이고, 이 자리는 그것만 지킨다.
struct RoomPresenceSection: View {
    private let entry: ChatRoomPolicy
    private let onChange: (RoomPolicy) -> Void

    init(entry: ChatRoomPolicy, onChange: @escaping (RoomPolicy) -> Void) {
        self.entry = entry
        self.onChange = onChange
    }

    var body: some View {
        RoomActiveHoursSection(hours: entry.policy.activeHours) { hours in
            var updated = entry.policy
            updated.activeHours = hours
            onChange(updated)
        }
    }
}
