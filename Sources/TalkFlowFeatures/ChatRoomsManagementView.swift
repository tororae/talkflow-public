import SwiftUI
import TalkFlowApplication
import TalkFlowDomain

struct ChatRoomsManagementView: View {
    @Bindable private var model: ChatRoomListModel
    private let summaryModel: RoomSummaryModel

    init(model: ChatRoomListModel, summaryModel: RoomSummaryModel) {
        self.model = model
        self.summaryModel = summaryModel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            roomList
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The settings arrive beside the list rather than splitting it. An
        // HSplitView re-divided the instant a room was picked — the heavy grouped
        // Form demanded width, the list was squeezed under its own fixed table
        // columns, and the whole pane jumped. An inspector keeps its own column,
        // so the list holds its width and the panel slides in over the space to
        // its right; closing it hands that width back.
        .inspector(isPresented: Binding(
            get: { model.selectedRoomID != nil },
            set: { shown in if !shown { model.selectedRoomID = nil } }
        )) {
            editor
                .inspectorColumnWidth(min: 340, ideal: 420, max: 680)
        }
        .navigationTitle("채팅방")
        .task { await model.loadIfNeeded() }
        // Re-read every time the screen is shown. Which windows are open is live
        // — the whole point of showing it is that opening one makes replies flow
        // — and a mark read once at first load would still say 닫힘 about a
        // window opened in response to it.
        .task { await model.refreshPresence() }
    }

    @ViewBuilder
    private var roomList: some View {
        if case let .failed(reason) = model.state {
            ContentUnavailableView(
                "채팅방을 불러오지 못했습니다",
                systemImage: "exclamationmark.triangle",
                description: Text(reason)
            )
        } else {
            Table(model.entries, selection: $model.selectedRoomID) {
                // The dot is how a pending edit survives being scrolled past.
                // Edits are kept per room so that opening another one to check
                // something does not throw them away, and a change the user can
                // no longer see is a change they will forget they made.
                TableColumn("채팅방") { entry in
                    HStack(spacing: 6) {
                        Text(entry.room.displayName)
                            .foregroundStyle(entry.isListedByKakaoTalk == false ? .secondary : .primary)
                        if model.unsavedRoomIDs.contains(entry.id) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 6))
                                .foregroundStyle(.orange)
                                .help("저장하지 않은 변경이 있습니다")
                        }
                        // Said as what is known, not as what is suspected.
                        // KakaoTalk's list only exposes the rows it has rendered,
                        // so a room below the fold reads exactly like one that was
                        // left — 「나간 방」 would be a claim this cannot support.
                        if entry.isListedByKakaoTalk == false {
                            Image(systemName: "eye.slash")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .help("카카오톡 대화 목록에 없습니다. 나간 방이거나, 목록에서 아래로 밀려 보이지 않는 방입니다.")
                        }
                    }
                    .contextMenu {
                        if entry.isHidden {
                            Button("목록에 다시 보이기") { Task { await model.unhide(entry) } }
                        } else {
                            Button("목록에서 숨기기") { Task { await model.hide(entry) } }
                        }
                    }
                }
                TableColumn("유형") { entry in
                    Label(
                        entry.room.kind == .direct ? "개인" : "단체",
                        systemImage: entry.room.kind == .direct ? "person" : "person.3"
                    )
                }
                .width(80)
                TableColumn("응답 정책") { entry in
                    Text(entry.policy.responseMode.title)
                        .foregroundStyle(entry.policy.responseMode == .off ? .secondary : .primary)
                }
                .width(120)
                // Beside the policy on purpose. Whether a room answers by itself
                // and whether its window is open are one question in practice:
                // automatic delivery will not open a closed room, so a room set
                // to answer with no window is a room whose replies are waiting.
                TableColumn("대화창") { entry in
                    windowState(entry)
                }
                .width(90)
                TableColumn("사용") { entry in
                    Toggle("사용", isOn: Binding(
                        get: { entry.policy.responseMode != .off },
                        set: { enabled in
                            Task { await model.setEnabled(enabled, for: entry) }
                        }
                    ))
                    .labelsHidden()
                }
                .width(50)
            }
            .frame(minHeight: 300)
        }
    }

    /// Three answers, and only one of them is a problem.
    ///
    /// A closed window matters when the room answers on its own and does not
    /// matter otherwise, so 「닫힘」 is only ever coloured in the case a person
    /// can do something about. Nothing at all when the window state could not be
    /// read — an unknown drawn as 닫힘 would send somebody opening windows that
    /// were never shut.
    @ViewBuilder
    private func windowState(_ entry: ChatRoomPolicy) -> some View {
        switch entry.hasOpenWindow {
        case true:
            Label("열림", systemImage: "macwindow")
                .foregroundStyle(.secondary)
                .help("이 방은 창이 열려 있어 화면을 건드리지 않고 1초 안에 보냅니다.")
        case false where entry.isBlockedByClosedWindow:
            Label("닫힘", systemImage: "macwindow.badge.plus")
                .foregroundStyle(.orange)
                .help("자동 전송이 켜져 있는데 대화창이 닫혀 있습니다. 답장이 대기만 하고 나가지 않습니다. 카카오톡에서 이 방을 열어두세요.")
        case false:
            Label("닫힘", systemImage: "macwindow")
                .foregroundStyle(.tertiary)
                .help("대화창이 닫혀 있습니다. 이 방은 자동 전송이 아니라 지금은 문제가 되지 않습니다.")
        case nil:
            Text("—").foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var editor: some View {
        if let entry = model.selectedEntry {
            RoomPolicyEditor(entry: entry, model: model, summaryModel: summaryModel)
        } else {
            ContentUnavailableView(
                "채팅방을 선택하세요",
                systemImage: "slider.horizontal.3",
                description: Text("방을 고르면 응답 모드와 전송 방식을 설정할 수 있습니다.")
            )
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("채팅방 관리").font(.largeTitle.bold())
                Text(model.summary).foregroundStyle(.secondary)
                // Ahead of the missing-room line, because this one is costing
                // replies right now and the other is only tidying.
                if model.roomsBlockedByClosedWindow > 0 {
                    Label(
                        "자동 전송인데 대화창이 닫힌 방 \(model.roomsBlockedByClosedWindow)개 · 카카오톡에서 열어두면 바로 나갑니다",
                        systemImage: "macwindow.badge.plus"
                    )
                    .font(.footnote)
                    .foregroundStyle(.orange)
                }
                // The list is derived from the archive and nothing is ever taken
                // out of it, so it only grows — one account here carries 234
                // rooms. This line is what turns that from a mystery into a
                // decision the user can make.
                if model.roomsMissingFromKakaoTalk > 0 {
                    Label(
                        "카카오톡 목록에 없는 방 \(model.roomsMissingFromKakaoTalk)개 · 방 이름을 오른쪽 클릭해 숨길 수 있습니다",
                        systemImage: "eye.slash"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                if model.hiddenRoomCount > 0 {
                    Button(model.showsHiddenRooms
                           ? "숨긴 방 감추기"
                           : "숨긴 방 \(model.hiddenRoomCount)개 보기") {
                        model.showsHiddenRooms.toggle()
                    }
                    .buttonStyle(.link)
                    .font(.footnote)
                }
            }
            Spacer()
            TextField("채팅방 검색", text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
            Button("새로고침") {
                Task { await model.reload() }
            }
        }
    }
}
