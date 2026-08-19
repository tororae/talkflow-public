import TalkFlowDomain

/// What KakaoTalk is showing right now: which rooms are in its chat list, and
/// which have a window open.
///
/// **Deliberately not part of loading the rooms.** The room list comes out of the
/// archive and is ready in microseconds; this drives KakaoTalk's own interface
/// and takes as long as KakaoTalk feels like taking — measured between 0.03s and
/// 2.6s, and it is a UI read, so there is no ceiling that does not come from a
/// timeout. Putting the two together left the screen on 「채팅방을 불러오는
/// 중입니다」 with nothing wrong except that a read had not come back.
///
/// So the rooms appear first and this arrives after, as marks on a list that is
/// already usable.
public struct InspectRoomPresence: Sendable {
    public struct Report: Equatable, Sendable {
        /// Names in KakaoTalk's chat list, when the answer was trustworthy.
        public let listedNames: Set<String>?
        /// Names with a chat window open on the active Space.
        public let openWindowNames: Set<String>?

        /// Folded to comparison keys once, rather than per room. The list can
        /// carry a couple of hundred rooms and rebuilding the key set for each
        /// of them is work that answers the same question every time.
        private let listedKeys: Set<String>?
        private let openWindowKeys: Set<String>?

        public init(listedNames: Set<String>?, openWindowNames: Set<String>?) {
            self.listedNames = listedNames
            self.openWindowNames = openWindowNames
            listedKeys = listedNames.map(RoomNameKey.set)
            openWindowKeys = openWindowNames.map(RoomNameKey.set)
        }

        public static let unknown = Report(listedNames: nil, openWindowNames: nil)

        /// Nil rather than false when nothing is known. A room drawn as
        /// 「목록에 없음」 because KakaoTalk was closed is an accusation made out
        /// of an unread answer.
        public func isListed(_ room: ChatRoom) -> Bool? {
            matches(room, in: listedKeys)
        }

        public func hasOpenWindow(_ room: ChatRoom) -> Bool? {
            matches(room, in: openWindowKeys)
        }

        /// Compared on `RoomNameKey`, because a group room nobody named is
        /// titled with its members and the two sources order them differently.
        /// As plain strings the same room read as two, and a room with its
        /// window open was marked 닫힘.
        private func matches(_ room: ChatRoom, in keys: Set<String>?) -> Bool? {
            keys.map { $0.contains(RoomNameKey.of(room.displayName)) }
        }
    }

    private let connection: any KakaoConnection

    public init(connection: any KakaoConnection) {
        self.connection = connection
    }

    public func callAsFunction() async -> Report {
        async let listed = connection.joinedRoomNames()
        async let open = connection.openRoomWindowNames()
        return Report(listedNames: await listed, openWindowNames: await open)
    }
}
