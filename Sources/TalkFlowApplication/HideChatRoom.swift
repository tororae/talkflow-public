import TalkFlowDomain

/// Takes a room out of the list, or puts it back.
///
/// Not a delete. The room list is derived from the archive — a room is in it
/// because a message once arrived — so removing the row would bring the room
/// back on the next load with its settings gone, which loses the configuration
/// and not the room.
///
/// It exists because the list only grows. Nothing is ever taken out of the
/// archive, so a room left three years ago sits beside the ones in use; one
/// account here carries 234 of them. KakaoTalk's own list can say which rooms it
/// is still showing, but only the rows it has rendered, so absence is a hint and
/// never a verdict — the app marks, and a person decides.
public struct HideChatRoom: Sendable {
    private let policyStore: any RoomPolicyStore

    public init(policyStore: any RoomPolicyStore) {
        self.policyStore = policyStore
    }

    public func callAsFunction(
        _ hidden: Bool,
        chatRoomID: String,
        accountFingerprint: String
    ) async throws {
        try await policyStore.setRoomHidden(
            hidden,
            chatRoomID: chatRoomID,
            accountFingerprint: accountFingerprint
        )
    }
}
