import SwiftUI
import TalkFlowApplication
import TalkFlowDomain

/// 집중 시간, inside 「얼마나 자주」 rather than in a section of its own.
///
/// It looks like a feature and is really a modifier. Every value here replaces
/// one of the three sitting directly above it — 끼어들기 확률, 최소 응답 간격,
/// 판단 주기 — and a user reading those three needs to know that a fourth thing
/// can quietly stand in for all of them. Given its own heading it would read as
/// an unrelated feature, and the three numbers above would go on looking like the
/// answer to "얼마나 자주" when sometimes they are not.
///
/// That is also why the fields are hidden until the switch is on. Nine controls
/// that describe a state the room is never in is how a screen stops being read;
/// off, this is one row.
struct RoomBurningSection: View {
    private let entry: ChatRoomPolicy
    private let onChange: (RoomPolicy) -> Void

    init(entry: ChatRoomPolicy, onChange: @escaping (RoomPolicy) -> Void) {
        self.entry = entry
        self.onChange = onChange
    }

    private var burning: BurningMode { entry.policy.burning }

    var body: some View {
        Section {
            SettingHelpRow("집중 시간", help: .burningMode) {
                Toggle("집중 시간", isOn: isEnabled)
                    .labelsHidden()
                    // A room switched off says nothing, and this is not the
                    // setting that reopens it — the same rule 먼저 말 걸기 follows.
                    .disabled(!answers)
            }

            if burning.isEnabled {
                SettingHelpRow("발동 확률", help: .burningChance) {
                    PercentField(
                        seedID: "\(entry.id)-burn-trigger",
                        title: "발동 확률",
                        chance: burning.chance
                    ) { chance in
                        var updated = entry.policy
                        updated.burning.chance = chance
                        onChange(updated)
                    }
                }

                SettingHelpRow("지속 시간", help: .burningDuration) {
                    IntervalRangeFields(
                        seedID: "\(entry.id)-burn-duration",
                        interval: burning.duration,
                        input: .burningDuration,
                        isEnabled: true
                    ) { parsed in
                        guard parsed != burning.duration else { return }
                        var updated = entry.policy
                        updated.burning.duration = parsed
                        onChange(updated)
                    }
                }

                SettingHelpRow("쿨타임", help: .burningCooldown) {
                    IntervalRangeFields(
                        seedID: "\(entry.id)-burn-cooldown",
                        interval: burning.cooldown,
                        input: .burningCooldown,
                        isEnabled: true
                    ) { parsed in
                        guard parsed != burning.cooldown else { return }
                        var updated = entry.policy
                        updated.burning.cooldown = parsed
                        onChange(updated)
                    }
                }

                // The three that stand in for the three above. Kept together and
                // labelled as a group, because reading them one at a time is how
                // 끼어들기 확률 appears twice on one screen meaning two things.
                SettingHelpRow("집중 중 설정값", help: .burningValues) {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("끼어들기 확률") {
                            PercentField(
                                seedID: "\(entry.id)-burn-chance",
                                title: "끼어들기 확률",
                                chance: burning.interjectionChance
                            ) { chance in
                                var updated = entry.policy
                                updated.burning.interjectionChance = chance
                                onChange(updated)
                            }
                        }
                        LabeledContent("최소 응답 간격") {
                            DurationField(
                                seedID: "\(entry.id)-burn-interval",
                                seconds: burning.minimumInterval,
                                presets: Self.burningIntervalPresets,
                                isEnabled: true
                            ) { seconds in
                                var updated = entry.policy
                                updated.burning.minimumInterval = seconds
                                onChange(updated)
                            }
                        }
                    }
                }
            }
        } header: {
            Text("집중 시간")
        } footer: {
            Text(note)
        }
    }

    private var answers: Bool {
        entry.policy.responseMode != .off && entry.policy.responseMode != .detectOnly
    }

    private var isEnabled: Binding<Bool> {
        Binding(
            get: { burning.isEnabled },
            set: { value in
                var updated = entry.policy
                updated.burning.isEnabled = value
                onChange(updated)
            }
        )
    }

    /// What this room does *now*, said in terms of the numbers just above rather
    /// than in general. The general explanation is behind the `?`; what a person
    /// reading this needs is which set of numbers is the one in force.
    private var note: String {
        guard answers else {
            return "응답 모드가 \"\(entry.policy.responseMode.title)\"이라 집중 시간도 동작하지 않습니다."
        }
        guard burning.isEnabled else {
            return "꺼져 있습니다. 이 방은 위의 값 그대로만 답합니다."
        }
        return """
        답할 때마다 \(burning.chance.summary) 확률로 집중 시간이 시작됩니다. \
        시작되면 그동안은 위의 세 값 대신 여기 적은 값으로 답하고, \
        끝나면 다시 위의 값으로 돌아갑니다. \
        답변 활성화 시간이 끝나면 집중 시간도 함께 끝납니다.
        """
    }

    /// Shorter than the presets on the setting it stands in for. A burn exists to
    /// make a room quick, and 15분 in this field would describe a room that is
    /// burning and silent at the same time.
    private static let burningIntervalPresets: [TimeInterval] = [0, 5, 15, 30, 60]
}
