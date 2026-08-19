import SwiftUI
import TalkFlowApplication
import TalkFlowDomain

/// One room's settings, arranged by the question each one answers.
///
/// They used to be fifteen controls in a single untitled block, in the order they
/// were built, every one of them writing to disk the moment it moved and saying
/// nothing about it. Two things are different here and both come from the same
/// complaint: a person could not tell what had applied, and could not tell what
/// the settings meant.
///
/// **One group at a time, chosen at the top.** 「언제 답하나」, 「언제 자리에 있나」,
/// 「얼마나 자주」, 「어떻게 말하나」, 「내보내기」 — the five questions the screen was
/// always organised by are a segmented control now, and only the chosen one's
/// settings are on screen. Stacking all five as cards put two tiers of headings on
/// top of each other and the eye could not find the seams; a tab is the group's
/// name, so each section keeps its own single heading underneath.
///
/// **Each question has a colour.** The picked tab and a bar above its settings
/// share one colour per group, so which of the five you are in reads at a glance
/// rather than off the heading text.
///
/// **The summary is first, and once.** It is the sentence that says what all of
/// this adds up to, pinned above the tabs in its own section rather than wrapped in
/// a second one that repeated its heading.
struct RoomPolicyEditor: View {
    private let entry: ChatRoomPolicy
    private let model: ChatRoomListModel
    private let summaryModel: RoomSummaryModel

    init(entry: ChatRoomPolicy, model: ChatRoomListModel, summaryModel: RoomSummaryModel) {
        self.entry = entry
        self.model = model
        self.summaryModel = summaryModel
    }

    /// Which of the five questions is on screen.
    @State private var group: Group = .answering

    /// Everything on this screen reads the edited copy, not the stored one, so
    /// 취소 has something to put back and the summary describes what 저장 would
    /// actually do.
    private var policy: RoomPolicy { model.editedPolicy(for: entry) }

    private var edited: ChatRoomPolicy {
        ChatRoomPolicy(room: entry.room, policy: policy)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Outside the scroll view on purpose. A save bar that scrolls away is
            // a save bar nobody finds when they need it, and this one also
            // carries the only report that a change took.
            RoomSaveBar(
                status: model.saveStatus,
                hasUnsavedChanges: model.hasUnsavedChanges(entry),
                onSave: { Task { await model.saveEdits(for: entry) } },
                onCancel: { model.revertEdits(for: entry) }
            )
            Divider()

            Form {
                // Pinned above the tabs: read first, checked after saving.
                RoomBehaviourSummary(entry: edited, cycle: model.judgementCycle)
                if model.hasUnsavedChanges(entry) {
                    Section {
                        Label(
                            "저장하면 이렇게 동작합니다. 아직 적용되지 않았습니다.",
                            systemImage: "info.circle"
                        )
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    }
                }

                // Shown only when a !세팅 write changed this room while an edit was
                // open here: the list already updated, but this screen's draft would
                // overwrite the change on 저장, so it offers to take the new value.
                if model.wasExternallyChanged(entry) {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(
                                "이 방 설정이 다른 곳에서 바뀌었습니다.",
                                systemImage: "exclamationmark.triangle"
                            )
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            Text("관리자 명령(!세팅)으로 바뀐 값입니다. 지금 편집을 저장하면 그 변경을 덮어씁니다.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("바뀐 값 불러오기 (편집 취소)") {
                                model.adoptExternalChange(for: entry)
                            }
                            .font(.footnote)
                        }
                    }
                }

                Section {
                    Picker("설정 그룹", selection: $group) {
                        ForEach(Group.allCases) { Text($0.tab).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .tint(group.color)
                }

                Section {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(group.color)
                            .frame(width: 4, height: 18)
                        Text(group.title)
                            .font(.headline)
                            .foregroundStyle(group.color)
                        Spacer()
                    }
                }

                groupContent
            }
            .formStyle(.grouped)
        }
        // Re-read whenever another room is opened: the call count, the cycle
        // deadline and the stored summary all belong to the room on screen, and
        // showing the previous room's would be worse than none.
        .task(id: entry.id) { await model.inspectRecentCalls(for: entry) }
        .task(id: entry.id) { await summaryModel.load(entry.room) }
    }

    @ViewBuilder
    private var groupContent: some View {
        switch group {
        case .answering:
            RoomAnsweringSection(entry: edited, model: model, onChange: change)
        case .presence:
            RoomPresenceSection(entry: edited, onChange: change)
        case .pacing:
            RoomPacingSection(entry: edited, onChange: change)
        case .voice:
            RoomVoiceSection(entry: edited, model: model, summaryModel: summaryModel, onChange: change)
        case .delivery:
            RoomDeliverySection(entry: edited, onChange: change)
        }
    }

    /// Every control routes through here, which is what keeps 저장 honest: there
    /// is one place a room is edited and one place it is written.
    private func change(_ policy: RoomPolicy) {
        model.edit(entry) { $0 = policy }
    }

    /// The five questions, each with a short tab label, a full title, and a colour
    /// that the tab and the bar above its settings share.
    private enum Group: CaseIterable, Identifiable {
        case answering, presence, pacing, voice, delivery

        var id: Self { self }

        var tab: String {
            switch self {
            case .answering: "답하나"
            case .presence: "자리"
            case .pacing: "자주"
            case .voice: "말하나"
            case .delivery: "내보내기"
            }
        }

        var title: String {
            switch self {
            case .answering: "언제 답하나"
            case .presence: "언제 자리에 있나"
            case .pacing: "얼마나 자주"
            case .voice: "어떻게 말하나"
            case .delivery: "내보내기"
            }
        }

        var color: Color {
            switch self {
            case .answering: .blue
            case .presence: .teal
            case .pacing: .orange
            case .voice: .purple
            case .delivery: .pink
            }
        }
    }
}
