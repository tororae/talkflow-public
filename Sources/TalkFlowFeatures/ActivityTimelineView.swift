import SwiftUI
import TalkFlowDomain

struct ActivityTimelineView: View {
    @Bindable private var model: ActivityTimelineModel

    init(model: ActivityTimelineModel) {
        self.model = model
    }

    var body: some View {
        VStack(spacing: 0) {
            ActivityFilterBar(model: model)
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The detail arrives beside the table rather than splitting it. An
        // HSplitView re-divided the moment a row was picked and squeezed the
        // list under its own fixed columns; an inspector keeps its own column,
        // so the table holds its width and the detail slides in over the space
        // to its right; closing it hands that width back.
        .inspector(isPresented: Binding(
            get: { model.selectedActionID != nil },
            set: { shown in if !shown { model.select(id: nil) } }
        )) {
            ActivityDetailView(model: model)
                .inspectorColumnWidth(min: 340, ideal: 420, max: 680)
        }
        .navigationTitle("활동")
        .toolbar {
            Button("새로고침") { Task { await model.reload() } }
        }
        .task { await model.reload() }
    }

    @ViewBuilder
    private var content: some View {
        if model.actions.isEmpty {
            ContentUnavailableView(
                "아직 기록된 활동이 없습니다",
                systemImage: "clock.arrow.circlepath",
                description: Text(model.failure ?? "메시지 감지, 답변 생성, 보류와 전송 결과가 이곳에 시간순으로 표시됩니다. 검토를 기다리는 초안도 여기서 보냅니다.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.visibleRows.isEmpty {
            ContentUnavailableView(
                "조건에 맞는 활동이 없습니다",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("위쪽 필터를 다시 켜면 나타납니다.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            table
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// One row per message rather than per recorded event, and a 단계 column
    /// saying how far it got.
    ///
    /// 결과 titles the row from the *newest* event: a message drafted and then sent
    /// has been sent, and a line still labelled 초안 would report the app as having
    /// stopped halfway. What the folded events were is in the detail pane, stage by
    /// stage — SwiftUI's `Table` has no disclosure row, so the summary here is a
    /// column and the full list stays one click away where it already was.
    private var table: some View {
        VStack(spacing: 0) {
            Table(model.visibleRows, selection: Binding(
                get: { model.selectedActionID },
                set: { model.select(id: $0) }
            )) {
                TableColumn("시각") { row in
                    Text(row.startedAt, format: .dateTime.month().day().hour().minute())
                }
                .width(110)
                TableColumn("채팅방") { row in
                    Text(row.latest.chatRoomName.isEmpty ? row.latest.chatRoomID : row.latest.chatRoomName)
                }
                TableColumn("결과") { row in
                    let isPending = model.isPending(row.latest)
                    Label(
                        ActivityKindStyle.title(for: row.latest, isPending: isPending),
                        systemImage: ActivityKindStyle.symbol(for: row.latest, isPending: isPending)
                    )
                    .foregroundStyle(ActivityKindStyle.tint(for: row.latest, isPending: isPending))
                }
                .width(100)
                TableColumn("단계") { row in
                    Text(stageSummary(row))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .width(150)
                TableColumn("내용") { row in
                    Text(row.latest.replyText ?? row.latest.detail)
                        .lineLimit(1)
                }
            }
            if model.canLoadMore {
                Divider()
                loadMoreButton
            }
        }
    }

    /// Sits under the table rather than in the toolbar because it is about the
    /// bottom of the list — the older history it fetches lands where the button
    /// is, not up in the chrome. Shown only while there is more to fetch, so its
    /// disappearance is how the list says it has reached the beginning.
    private var loadMoreButton: some View {
        Button {
            Task { await model.loadMore() }
        } label: {
            HStack(spacing: 6) {
                if model.isLoadingMore {
                    ProgressView().controlSize(.small)
                    Text("불러오는 중…")
                } else {
                    Image(systemName: "arrow.down.circle")
                    Text("이전 기록 더 보기")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(model.isLoadingMore)
    }

    /// 「답변까지 · 12.3초」, and the count only when something was actually folded.
    ///
    /// The elapsed figure is the whole message's, which is the number somebody who
    /// came here about a slow reply is looking for. It is omitted rather than shown
    /// as 0초 for a row with a single stamp: one stamp records that something
    /// happened, not that it took no time.
    private func stageSummary(_ row: ActivityRow) -> String {
        var parts = [row.reach.title]
        if let seconds = row.timeline.duration, seconds >= 1 {
            parts.append("\(seconds.formatted(.number.precision(.fractionLength(1))))초")
        }
        if row.eventCount > 1 {
            parts.append("기록 \(row.eventCount)개")
        }
        return parts.joined(separator: " · ")
    }
}
