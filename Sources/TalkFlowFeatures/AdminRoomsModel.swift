import Foundation
import Observation
import TalkFlowDomain

/// State for the 관리자 모드 section of 설정: which rooms are consoles, and the live
/// rooms available to make one.
///
/// This is the only place admin mode is turned on or off — there is no per-room
/// toggle in the room editor, because a console is not a way a room *answers*, it
/// is a room the operator drives the app from.
///
/// The picker reads the account's **live** rooms (`connection.chatRooms()`), not
/// the archive-accumulated list the 채팅방 screen manages: that list only grows and
/// carries rooms left years ago, and a console is designated for a room the
/// operator is in now.
@MainActor
@Observable
public final class AdminRoomsModel {
    public enum State: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    /// A designated console, drawn as a row. Carries whether KakaoTalk still lists
    /// the room so one turned on for a room that has since dropped off the list
    /// still shows — and can be removed — while saying it is no longer listed.
    public struct AdminRoomEntry: Identifiable, Equatable, Sendable {
        public let id: String
        public let name: String
        public let isListed: Bool
    }

    public private(set) var state: State = .idle
    public private(set) var adminRooms: [AdminRoomEntry] = []
    /// Narrows the add-picker. The list can be long — one account here carries 234
    /// rooms — so adding one is a search, not a scroll.
    public var searchText = ""
    /// A write that failed, kept apart from `state` because the list on screen is
    /// still valid; only the last add or remove did not take.
    public private(set) var failure: String?

    private var liveRooms: [ChatRoom] = []
    private var adminIDs: Set<String> = []
    private var fingerprint: String?

    private let connection: any KakaoConnection
    /// Nil without a database, exactly as the other stores are. Nothing can be
    /// read or written then and the section says so, rather than drawing an empty
    /// list that reads as no room having been designated.
    private let store: (any AdminRoomStore)?

    public init(connection: any KakaoConnection, store: (any AdminRoomStore)?) {
        self.connection = connection
        self.store = store
    }

    /// The rooms the picker offers: live rooms not already a console, narrowed by
    /// the search. Sorted the way every room list in the app is.
    public var pickerRooms: [ChatRoom] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return liveRooms.filter { room in
            guard !adminIDs.contains(room.id) else { return false }
            guard !query.isEmpty else { return true }
            return room.displayName.localizedCaseInsensitiveContains(query)
        }
    }

    public var summary: String {
        switch state {
        case .idle, .loading:
            return "관리자 방을 불러오는 중입니다."
        case .loaded:
            return adminRooms.isEmpty ? "지정된 관리자 방이 없습니다." : "관리자 방 \(adminRooms.count)곳"
        case let .failed(reason):
            return reason
        }
    }

    public func loadIfNeeded() async {
        if case .loaded = state { return }
        await reload()
    }

    public func reload() async {
        guard let store else {
            state = .failed("관리자 방을 저장할 곳을 열지 못했습니다. 이 Mac의 데이터베이스에 저장됩니다.")
            return
        }
        state = .loading
        guard case let .connected(account) = await connection.status() else {
            state = .failed("카카오톡에 연결되어 있지 않습니다. 계정을 확인한 뒤 다시 시도하세요.")
            return
        }
        fingerprint = account.fingerprint
        do {
            let rooms = try await connection.chatRooms()
                .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            let ids = try await store.adminRoomIDs(accountFingerprint: account.fingerprint)
            liveRooms = rooms
            adminIDs = ids
            rebuildAdminRooms()
            failure = nil
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public func add(_ room: ChatRoom) async {
        guard let store, let fingerprint else { return }
        do {
            try await store.setAdminRoom(true, chatRoomID: room.id, accountFingerprint: fingerprint)
            adminIDs.insert(room.id)
            rebuildAdminRooms()
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }

    public func remove(_ entry: AdminRoomEntry) async {
        guard let store, let fingerprint else { return }
        do {
            try await store.setAdminRoom(false, chatRoomID: entry.id, accountFingerprint: fingerprint)
            adminIDs.remove(entry.id)
            rebuildAdminRooms()
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }

    /// A console whose room is no longer live shows under its id rather than being
    /// dropped, so the operator can still take it off.
    private func rebuildAdminRooms() {
        let byID = Dictionary(liveRooms.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        adminRooms = adminIDs
            .map { id in
                AdminRoomEntry(id: id, name: byID[id]?.displayName ?? id, isListed: byID[id] != nil)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
