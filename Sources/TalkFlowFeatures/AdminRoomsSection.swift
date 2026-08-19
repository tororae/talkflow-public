import SwiftUI
import TalkFlowDomain

/// The 관리자 모드 section of 설정: the rooms slash-commands are honored in, and a
/// searchable picker to designate one.
///
/// The warning above the list is load-bearing, not decoration. A console trusts
/// every message in the room as a command — that is the app's one carve-out of
/// its "message text is never an instruction" rule — so the section says plainly
/// that anyone in the room can drive TalkFlow from it.
struct AdminRoomsSection: View {
    @Bindable private var model: AdminRoomsModel

    init(model: AdminRoomsModel) {
        self.model = model
    }

    /// How many picker matches are drawn before it stops and asks for a narrower
    /// search. The full list can be hundreds of rooms.
    private static let pickerCap = 8

    var body: some View {
        Section {
            Text("이 방에서는 ! 로 시작하는 명령을 입력하면 TalkFlow가 그 방에 답합니다. !? 로 명령 목록을 봅니다. 응답이 꺼진 방에서도 명령은 동작합니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            // Said where the switch is, because this is the one place the app
            // executes what a message says. 방 안 누구든 명령을 쓸 수 있다.
            Text("주의: 이 방에 있는 누구나 명령을 쓸 수 있습니다. 신뢰하는 방만 지정하세요.")
                .font(.footnote)
                .foregroundStyle(.orange)

            content

            if let failure = model.failure {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("관리자 모드")
        }
        .task { await model.loadIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            Text("관리자 방을 불러오는 중입니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case let .failed(reason):
            Label(reason, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.orange)
        case .loaded:
            designatedRooms
            addPicker
        }
    }

    @ViewBuilder
    private var designatedRooms: some View {
        if model.adminRooms.isEmpty {
            Text("지정된 관리자 방이 없습니다. 아래에서 검색해 추가하세요.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            ForEach(model.adminRooms) { entry in
                HStack(spacing: 6) {
                    Text(entry.name)
                        .foregroundStyle(entry.isListed ? .primary : .secondary)
                    if !entry.isListed {
                        Image(systemName: "eye.slash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("카카오톡 대화 목록에 없는 방입니다. 나갔거나 목록에서 밀려 보이지 않는 방일 수 있습니다.")
                    }
                    Spacer()
                    Button {
                        Task { await model.remove(entry) }
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("관리자 방에서 제외")
                }
            }
        }
    }

    @ViewBuilder
    private var addPicker: some View {
        TextField("방 이름으로 검색해서 추가", text: $model.searchText)
            .textFieldStyle(.roundedBorder)

        let matches = model.pickerRooms
        if matches.isEmpty {
            Text(model.searchText.trimmingCharacters(in: .whitespaces).isEmpty
                 ? "추가할 수 있는 방이 없습니다."
                 : "검색 결과가 없습니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            ForEach(Array(matches.prefix(Self.pickerCap))) { room in
                Button {
                    Task { await model.add(room) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                        Text(room.displayName)
                        Spacer()
                        Text(room.kind == .direct ? "개인" : "단체")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.borderless)
            }
            if matches.count > Self.pickerCap {
                Text("…\(matches.count - Self.pickerCap)개 더 · 검색으로 좁히세요")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
