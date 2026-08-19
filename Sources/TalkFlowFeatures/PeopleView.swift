import Foundation
import SwiftUI
import TalkFlowDomain

/// 사람: everybody TalkFlow has written a note about, and what it wrote.
///
/// The room picker at the top is a way of finding somebody. It is not a scope, and
/// the screen is built to keep saying so: every row carries the rooms that person
/// is in rather than the one being filtered by, the open person stays open when
/// the filter moves off their room, and the detail pane leads with 함께 있는 방
/// before it shows a word of the note. A note is one per person — 강민석 is in five
/// of this account's rooms and reads the same in all five — and a picker at the top
/// of a screen is otherwise read as saying the opposite.
struct PeopleView: View {
    @Bindable private var model: PeopleModel

    init(model: PeopleModel) {
        self.model = model
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            roomFilter
            peopleList
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The note arrives beside the list rather than splitting it. An
        // HSplitView re-divided the moment somebody was picked — the editor
        // demanded width, the list was squeezed under its own fixed table
        // columns, and the pane jumped. An inspector keeps its own column, so
        // the list holds its width and the note slides in over the space to its
        // right; closing it hands that width back.
        .inspector(isPresented: Binding(
            get: { model.selectedEntryID != nil },
            set: { shown in if !shown { model.selectedEntryID = nil } }
        )) {
            editor
                .inspectorColumnWidth(min: 340, ideal: 420, max: 680)
        }
        .navigationTitle("사람")
        .task { await model.loadIfNeeded() }
        // Read again every time the tab comes up. The notes underneath are
        // written by the summary sweep with nobody watching, so unlike every
        // other screen here this one is looking at data that moves on its own.
        .onAppear { Task { await model.refreshQuietly() } }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("사람").font(.largeTitle.bold())
                Text(model.summary).foregroundStyle(.secondary)
            }
            Spacer()
            TextField("사람 검색", text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
            Button("새로고침") {
                Task { await model.reload() }
            }
        }
    }

    /// The picker and the sentence that says what it does. The sentence is not
    /// decoration: a control that narrows a list of people, sitting above an
    /// editor, is read as choosing which room's note is being edited, and that
    /// reading is wrong in a way the user would only discover by finding their
    /// edit in another room.
    @ViewBuilder
    private var roomFilter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("채팅방", selection: $model.roomFilterID) {
                Text("모든 방").tag(String?.none)
                ForEach(model.filterRooms) { room in
                    Text(room.displayName).tag(String?.some(room.id))
                }
            }
            .frame(maxWidth: 320)
            .disabled(model.filterRooms.isEmpty)

            Text("방은 사람을 찾는 데만 씁니다. 메모는 사람마다 하나라, 어느 방을 골라도 같은 메모를 봅니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var peopleList: some View {
        switch model.state {
        case let .failed(reason):
            ContentUnavailableView(
                "사람 메모를 불러오지 못했습니다",
                systemImage: "exclamationmark.triangle",
                description: Text(reason)
            )
        case .idle, .loading:
            ContentUnavailableView {
                Label("불러오는 중입니다", systemImage: "person.crop.circle")
            } description: {
                Text("방마다 누구에 대해 적어 두었는지 확인하고 있습니다.")
            }
        case .loaded where model.people.isEmpty:
            // Says what would produce one rather than only that there are none.
            // 사람 기억 ships off in every room, so an account that has never
            // turned it on looks exactly like one whose people were all deleted.
            ContentUnavailableView(
                "아직 기억하는 사람이 없습니다",
                systemImage: "person.crop.circle.badge.questionmark",
                description: Text("채팅방 설정에서 \"사람 기억\"을 켠 방에서, 답장이 오간 사람부터 여기에 쌓입니다.")
            )
        case .loaded where model.entries.isEmpty:
            ContentUnavailableView(
                "찾는 사람이 없습니다",
                systemImage: "magnifyingglass",
                description: Text("검색어나 방 선택을 바꿔 보세요. 메모는 사람마다 하나라 방을 바꿔도 사라지지 않습니다.")
            )
        case .loaded:
            table
        }
    }

    private var table: some View {
        Table(model.entries, selection: $model.selectedEntryID) {
            TableColumn("사람") { entry in
                HStack(spacing: 6) {
                    Text(entry.note.displayName)
                    // The whole reason a list of people can be used at all. Mina is
                    // two different people in this account's rooms, and in one room
                    // the two rows would otherwise be identical.
                    if let idTail = entry.idTail {
                        Text("…\(idTail)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .help("이 방에 같은 이름을 쓰는 사람이 또 있습니다. 발신자 아이디 뒷자리로 구분합니다.")
                    }
                    // A pending edit that scrolled out of sight is one the user
                    // will forget they made — the same dot, for the same reason,
                    // as the room list.
                    if model.unsavedEntryIDs.contains(entry.id) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(.orange)
                            .help("저장하지 않은 변경이 있습니다")
                    }
                }
            }

            // Half the key, so it is a column and not a detail. The same person in
            // two rooms is two rows here, and this is the only thing on the row
            // that says which is which.
            TableColumn("방") { entry in
                Text(entry.roomLabel)
                    .foregroundStyle(.secondary)
                    .help("이 메모는 \(entry.room.displayName)에서의 이 사람에 대한 것입니다.")
            }
            .width(min: 140, ideal: 180)

            TableColumn("마지막 저장") { entry in
                Text(Self.stamp.string(from: entry.note.updatedAt))
                    .foregroundStyle(.secondary)
            }
            .width(100)
        }
        .frame(minHeight: 300)
    }

    @ViewBuilder
    private var editor: some View {
        if let entry = model.selectedEntry {
            PeopleNoteEditor(entry: entry, model: model)
        } else {
            ContentUnavailableView(
                "사람을 선택하세요",
                systemImage: "person.text.rectangle",
                description: Text("고른 사람에 대해 적어 둔 글과 링크를 읽고, 고치고, 지울 수 있습니다.")
            )
        }
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()
}
