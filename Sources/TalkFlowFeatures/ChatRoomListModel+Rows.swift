import TalkFlowApplication
import TalkFlowDomain

/// What 채팅방 draws: the visible rows, the marks KakaoTalk supplies, the counts
/// under the table, and the values a room shows for the settings it follows.
/// All derived from the loaded board, so no reader here can disagree with it.
@MainActor
extension ChatRoomListModel {
    /// Hidden rooms are out of the list unless asked for. Filtered here rather
    /// than when they are loaded, so the way back to them is always one toggle
    /// and never a lost room.
    public var entries: [ChatRoomPolicy] {
        guard case let .loaded(board) = state else { return [] }
        let visible = board.entries
            .filter { showsHiddenRooms || !$0.isHidden }
            .map(marked)
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return visible }
        return visible.filter { $0.room.displayName.localizedCaseInsensitiveContains(query) }
    }

    /// Lays what KakaoTalk is showing over what the archive knows. Both marks are
    /// nil until the first reading comes back, which is how the list draws
    /// nothing rather than something wrong in the seconds before it does.
    private func marked(_ entry: ChatRoomPolicy) -> ChatRoomPolicy {
        ChatRoomPolicy(
            room: entry.room,
            policy: entry.policy,
            isListedByKakaoTalk: presence.isListed(entry.room),
            isHidden: entry.isHidden,
            hasOpenWindow: presence.hasOpenWindow(entry.room)
        )
    }

    public var hiddenRoomCount: Int {
        guard case let .loaded(board) = state else { return 0 }
        return board.entries.filter(\.isHidden).count
    }

    public var selectedEntry: ChatRoomPolicy? {
        guard case let .loaded(board) = state, let selectedRoomID else { return nil }
        return board.entries.first { $0.id == selectedRoomID }
    }

    public var summary: String {
        switch state {
        case .idle, .loading:
            return "채팅방을 불러오는 중입니다."
        case let .loaded(board):
            let active = board.entries.filter { $0.policy.responseMode != .off }.count
            let direct = board.entries.filter { $0.room.kind == .direct }.count
            return "전체 \(board.entries.count)개 · 개인 \(direct)개 · 단체 \(board.entries.count - direct)개 · 응답 켠 방 \(active)개"
        case let .failed(reason):
            return reason
        }
    }

    /// The words this room answers to: the account's own name, the keywords every
    /// room shares, and this room's own.
    public func callSigns(for entry: ChatRoomPolicy) -> CallSigns {
        guard case let .loaded(board) = state else { return CallSigns() }
        let signs = board.callSigns(for: entry)
        // The room's own name wins where it has one. The board carries the
        // account-wide name because it is loaded once for every room, and the
        // room's own is read when that room is opened.
        guard let roomNickname = recentCalls?.roomNickname else { return signs }
        return CallSigns(
            nickname: roomNickname,
            globalKeywords: signs.globalKeywords,
            roomKeywords: signs.roomKeywords
        )
    }

    /// Whether a name was read from this room's own history rather than from the
    /// account-wide lookup.
    ///
    /// It does *not* mean the name is this room's. KakaoTalk stamps the account
    /// name on every outgoing message and never the per-room one, so both reads
    /// return the same string and only their dating differs — measured on
    /// 2026-08-11 in a room named 「호두과자」 that recorded 「달구지톡」 on every
    /// message sent to it. The label this drives says 계정 이름 either way, because
    /// the previous one said 「내 이름 (이 방)」 and had the screen claiming to know
    /// something no row anywhere holds.
    public var readNicknameFromThisRoom: Bool {
        recentCalls?.roomNickname != nil
    }

    /// What 설정 holds right now, so a room can show what it is following and
    /// start from it when an override is switched on.
    public var globalStyle: ResponseStyle {
        guard case let .loaded(board) = state else { return ResponseStyle() }
        return board.globalStyle
    }

    public var globalCondition: AnsweringCondition {
        guard case let .loaded(board) = state else { return .empty }
        return board.globalCondition
    }

    /// Rooms KakaoTalk is no longer showing, which is the closest thing to
    /// 「나간 방」 that anything here can know. It is not proof — the list only
    /// exposes rendered rows — so this counts them for a hint rather than acting.
    public var roomsMissingFromKakaoTalk: Int {
        entries.filter { $0.isListedByKakaoTalk == false }.count
    }

    /// Rooms set to answer on their own that cannot, because their chat window is
    /// closed. The one state on this screen a person can fix in a second.
    public var roomsBlockedByClosedWindow: Int {
        entries.filter(\.isBlockedByClosedWindow).count
    }
}
