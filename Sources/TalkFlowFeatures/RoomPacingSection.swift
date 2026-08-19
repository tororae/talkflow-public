import SwiftUI
import TalkFlowApplication
import TalkFlowDomain

/// 얼마나 자주 — the three limits on how often this room may speak, with 집중 시간
/// beneath them: the temporary override that can stand in for all three.
///
/// Together because they were unreadable apart. Three settings bound the same
/// thing by different means: a coin flip per message, a batching cycle, and a
/// floor between replies. Scattered down a flat form they read as three unrelated
/// numbers, and the user had no way to see that turning one on switches another
/// off. The footer says which one is actually in force.
struct RoomPacingSection: View {
    let entry: ChatRoomPolicy
    let onChange: (RoomPolicy) -> Void

    var body: some View {
        Section {
            RoomInterjectionChanceRow(
                roomID: entry.id,
                chance: entry.policy.interjectionChance,
                isEnabled: entry.policy.responseMode == .automatic
            ) { chance in
                var updated = entry.policy
                updated.interjectionChance = chance
                onChange(updated)
            }

            RoomJudgementIntervalRow(
                roomID: entry.id,
                interval: entry.policy.judgementInterval
            ) { interval in
                var updated = entry.policy
                updated.judgementInterval = interval
                onChange(updated)
            }

            SettingHelpRow("최소 응답 간격", help: .minimumInterval) {
                DurationField(
                    seedID: entry.id,
                    seconds: entry.policy.minimumInterval,
                    presets: Self.intervalPresets,
                    // Both bound how often the room may speak, so only one is
                    // ever in force. Leaving the other editable would let a user
                    // set a number that quietly does nothing.
                    isEnabled: !entry.policy.judgesInBatches
                ) { seconds in
                    var updated = entry.policy
                    updated.minimumInterval = seconds
                    onChange(updated)
                }
            }
        } header: {
            Text("얼마나 자주")
        } footer: {
            Text(governing)
        }

        RoomBurningSection(entry: entry, onChange: onChange)
    }

    /// Names the setting that is actually deciding the pace right now. Three
    /// numbers on screen and only one of them doing anything is the confusion
    /// this line exists to end.
    private var governing: String {
        if entry.policy.responseMode == .off || entry.policy.responseMode == .detectOnly {
            return "이 방은 답하지 않도록 되어 있어 아래 값들은 쓰이지 않습니다."
        }
        if entry.policy.burning.isEnabled {
            return burningNote
        }
        if entry.policy.judgesInBatches {
            return "지금은 판단 주기가 이 방의 속도를 정합니다. 최소 응답 간격은 쓰이지 않습니다."
        }
        if entry.policy.minimumInterval > 0 {
            return "지금은 최소 응답 간격이 이 방의 속도를 정합니다."
        }
        return "지금은 속도 제한이 없습니다. 끼어들기 확률만 답할지를 정합니다."
    }

    /// 집중 시간이 이제 이 그룹 바로 아래에 있으니, 이 줄은 평상값과 집중값을 잇는
    /// 다리다. 푸터는 지금 실제로 속도를 정하는 값을 짚는 자리이고, 집중이 발동하면
    /// 위의 어느 값도 그 일을 하지 않는다.
    private var burningNote: String {
        let governing = entry.policy.judgesInBatches
            ? "판단 주기"
            : (entry.policy.minimumInterval > 0 ? "최소 응답 간격" : "끼어들기 확률")
        return """
        평소에는 \(governing)이 이 방의 속도를 정합니다. 집중 시간이 시작되면 위의 값 대신 아래 \"집중 시간\"에 적은 값이 쓰입니다.
        """
    }

    /// The answers people actually give, with 직접 입력 for the ones they do not.
    private static let intervalPresets: [TimeInterval] = [0, 60, 300, 900, 3600]
}
