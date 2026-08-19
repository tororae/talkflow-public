import TalkFlowApplication
import TalkFlowDomain

/// Loading the board, writing a policy to the store, hiding a room, and asking
/// KakaoTalk what it is showing.
///
/// Kept apart from the unsaved-edit half because these are the calls that can
/// fail on the way out of the app, and every one of them ends by replacing the
/// board rather than by touching a draft.
@MainActor
extension ChatRoomListModel {
    public func loadIfNeeded() async {
        if case .loaded = state { return }
        await reload()
    }

    public func reload() async {
        state = .loading
        do {
            state = .loaded(try await loadRooms())
            // After the rooms, never before them. This one drives KakaoTalk's
            // interface, and a list that waited on it sat on 「불러오는 중」 with
            // nothing wrong except that a read had not come back.
            Task { await refreshPresence() }
        } catch let error as RoomPolicyLoadError {
            switch error {
            case let .accountNotVerified(reason):
                state = .failed(reason)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Writes the change to disk first: a switch that flips in the UI but never
    /// reaches the store would tell the user a room is on when it is not.
    public func update(_ policy: RoomPolicy) async {
        guard case let .loaded(board) = state else { return }
        do {
            try await saveRoomPolicy(policy)
        } catch {
            state = .failed(error.localizedDescription)
            return
        }

        let entries = board.entries.map { entry in
            entry.room.id == policy.chatRoomID
                ? ChatRoomPolicy(room: entry.room, policy: policy)
                : entry
        }
        state = .loaded(
            RoomPolicyBoard(
                accountFingerprint: board.accountFingerprint,
                accountNickname: board.accountNickname,
                globalStyle: board.globalStyle,
                globalCondition: board.globalCondition,
                entries: entries
            )
        )

        // Changing how long this room accumulates changes when it next speaks,
        // and the line saying so would otherwise keep describing the setting the
        // user just replaced.
        guard let changed = entries.first(where: { $0.id == policy.chatRoomID }),
              changed.id == selectedRoomID
        else {
            return
        }
        await refreshJudgementCycle(for: changed)
    }

    /// Takes a room out of the list without touching what it was configured to
    /// do.
    ///
    /// Not a delete, because there is nothing to delete: the list is derived from
    /// the archive and a room is in it because a message once arrived. Hiding is
    /// the only honest word for what happens, and it is reversible — 숨긴 방 보기
    /// gives them back exactly as they were set up.
    public func hide(_ entry: ChatRoomPolicy) async {
        guard case let .loaded(board) = state else { return }
        try? await setHidden(true, entry: entry, fingerprint: board.accountFingerprint)
        if selectedRoomID == entry.id { selectedRoomID = nil }
        await reload()
    }

    public func unhide(_ entry: ChatRoomPolicy) async {
        guard case let .loaded(board) = state else { return }
        try? await setHidden(false, entry: entry, fingerprint: board.accountFingerprint)
        await reload()
    }

    private func setHidden(_ hidden: Bool, entry: ChatRoomPolicy, fingerprint: String) async throws {
        try await hideRoom(hidden, chatRoomID: entry.room.id, accountFingerprint: fingerprint)
    }

    /// Asks KakaoTalk what it is showing, and marks the list with the answer.
    ///
    /// Failure is silent and leaves every mark unknown: this decorates a list
    /// that already works, and a room screen that reported an error because a UI
    /// read did not come back would be reporting the wrong thing.
    public func refreshPresence() async {
        presence = await inspectPresence()
    }

    /// One switch turns a room on, using the mode that suits its type.
    ///
    /// The one control on this screen that still writes immediately, and
    /// deliberately: it lives in the list rather than in the editor, and turning
    /// a room off from there is the gesture somebody makes when a room is
    /// misbehaving right now. A stop that waited for 저장 would not be a stop.
    public func setEnabled(_ enabled: Bool, for entry: ChatRoomPolicy) async {
        var policy = entry.policy
        policy.responseMode = enabled ? RoomPolicy.initialEnabledMode(for: entry.room) : .off
        await update(policy)
    }
}
