import SwiftUI
import TalkFlowDomain

/// The row of checkboxes above the 활동 table, plus the room popover.
///
/// Rooms get a popover rather than more checkboxes because there is no upper
/// bound on how many there are, and a bar that wraps to four lines stops being
/// a bar.
struct ActivityFilterBar: View {
    @Bindable private var model: ActivityTimelineModel
    @State private var showsRoomPicker = false

    init(model: ActivityTimelineModel) {
        self.model = model
    }

    /// Two rows, because there are two questions. 결과 is what the app decided;
    /// 단계 is how far it got before deciding. They were one row of five boxes
    /// while 단계 did not exist, and eleven boxes on one line wraps into something
    /// that is no longer a bar.
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 16) {
                Text("결과").font(.caption).foregroundStyle(.secondary).frame(width: 30, alignment: .leading)
                ForEach(ActivityFilter.Category.allCases) { category in
                    Toggle(category.title, isOn: Binding(
                        get: { model.filter.categories.contains(category) },
                        set: { model.filter.setCategory(category, included: $0) }
                    ))
                    .toggleStyle(.checkbox)
                }

                Divider().frame(height: 16)

                // Its own box, apart from the 결과 group and never swept by 전체
                // 선택/해제: 관리자 명령 are console operations, not message outcomes.
                Toggle("관리자", isOn: Binding(
                    get: { model.filter.showsCommands },
                    set: { model.filter.setShowsCommands($0) }
                ))
                .toggleStyle(.checkbox)
                .help("관리자 콘솔 명령 기록. 전체 선택·해제와 따로 켜고 끕니다.")

                Divider().frame(height: 16)

                Button { showsRoomPicker = true } label: {
                    Label(model.filter.roomSummary, systemImage: "bubble.left.and.bubble.right")
                }
                .popover(isPresented: $showsRoomPicker, arrowEdge: .bottom) {
                    ActivityRoomPicker(model: model)
                }

                Spacer(minLength: 12)

                if let pending = model.pendingSummary {
                    Label(pending, systemImage: "tray.full")
                        .foregroundStyle(.tint)
                        .fontWeight(.medium)
                }
                Text(model.summary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 16) {
                Text("단계").font(.caption).foregroundStyle(.secondary).frame(width: 30, alignment: .leading)
                ForEach(ActionReach.allCases) { reach in
                    Toggle(reach.title, isOn: Binding(
                        get: { model.filter.reaches.contains(reach) },
                        set: { model.filter.setReach(reach, included: $0) }
                    ))
                    .toggleStyle(.checkbox)
                    .help(reach.explanation)
                }

                Divider().frame(height: 16)

                // 결과·단계 두 축만. 채팅방은 팝오버의 자체 버튼으로, 관리자 명령은 위
                // 「관리자」 체크박스로 따로 — 이 한 쌍이 그 둘을 건드리지 않는다.
                Button("전체 선택") { model.filter.selectAll() }
                    .disabled(model.filter.allResultAndStageOn)
                Button("전체 해제") { model.filter.clearAll() }
                    .disabled(model.filter.allResultAndStageOff)

                Spacer(minLength: 12)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The room list behind the filter bar's popover.
private struct ActivityRoomPicker: View {
    @Bindable var model: ActivityTimelineModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("채팅방 필터").font(.headline)
                Spacer()
                Button("전체 선택") { model.filter.selectAllRooms() }
                Button("모두 해제") { model.filter.clearRooms() }
            }

            Divider()

            if model.roomOptions.isEmpty {
                Text("기록이 있는 채팅방이 아직 없습니다.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                rooms
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    private var rooms: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(model.roomOptions) { room in
                    Toggle(isOn: Binding(
                        get: { model.filter.includesRoom(room.id) },
                        set: { model.setRoom(room.id, included: $0) }
                    )) {
                        HStack {
                            Text(room.name).lineLimit(1)
                            Spacer()
                            Text("\(room.count)")
                                .monospacedDigit()
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .toggleStyle(.checkbox)
                    .accessibilityLabel("\(room.name) 기록 \(room.count)건")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 260)
    }
}
