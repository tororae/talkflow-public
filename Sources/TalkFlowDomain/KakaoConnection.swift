import Foundation

public enum KakaoConnectionStatus: Equatable, Sendable {
    case disconnected
    case unavailable(reason: String)
    case connected(account: AccountProfile)
}

public protocol KakaoConnection: Sendable {
    func status() async -> KakaoConnectionStatus
    func chatRooms() async throws -> [ChatRoom]
    func recentMessages(in chatRoom: ChatRoom, limit: Int) async throws -> [ChatMessage]

    /// The account's own name as the newest message it sent in this room carries
    /// it.
    ///
    /// Not the name the user set for themselves *in* that room. KakaoTalk lets one
    /// account carry a different name per chat, and this cannot see it: outgoing
    /// messages are stamped with the account name and nothing else, so a per-room
    /// rename appears nowhere in the archive. Measured on 2026-08-11 — a room whose
    /// name was 「호두과자」 recorded 「달구지톡」 on every message the account sent to
    /// it, including one typed by hand to check. The room-scoped read is still worth
    /// doing, because it dates the answer to this room's own history, but what comes
    /// back is the account's name. A per-room name has to be registered as one of
    /// that room's keywords, and the help card says so.
    func accountNickname(in chatRoom: ChatRoom) async -> String?

    /// Drops any remembered account name so the next read goes to the archive.
    ///
    /// Exists because the one thing the name changes for — the user renaming
    /// themselves — was the one thing the cache holding it could not notice. It
    /// expires on its own now; this is the button for somebody who has just done
    /// the renaming and is watching the screen.
    func forgetAccountNickname() async

    /// The names KakaoTalk is showing in its own chat list right now.
    ///
    /// The archive cannot answer this. A room is in it because a message once
    /// arrived, and nothing is ever taken out — so a room left three years ago
    /// sits in the list beside the ones in use, and the list only grows. One
    /// account here has 234 of them.
    ///
    /// **Names, and only the ones on screen.** KakaoTalk's list exposes visible
    /// rows only (`PLATFORM-FINDINGS.md` §3.5), so a room's absence means either
    /// that it was left or that it was below the fold, and nothing here can tell
    /// those apart. Presence is the sound half: a name in this list is a room
    /// this account is certainly still in.
    ///
    /// Nil when the list could not be read at all, which must not be confused
    /// with an empty list — one says nothing is known, the other says every room
    /// is gone.
    func joinedRoomNames() async -> Set<String>?

    /// The rooms whose chat window is open right now.
    ///
    /// The one thing that decides whether a reply can go out without moving
    /// anything on screen. A room with its window open is typed into directly in
    /// about a second; a room without one needs KakaoTalk driven to open it,
    /// which automatic delivery refuses to do — so an auto-sending room with no
    /// window is a room whose replies are waiting.
    ///
    /// Only the active Space, because that is all accessibility can see
    /// (`PLATFORM-FINDINGS.md` §3.1). A window on another desktop reads as
    /// closed.
    func openRoomWindowNames() async -> Set<String>?
}

public extension KakaoConnection {
    /// A source that does not know about per-room names says so, rather than
    /// answering with the account-wide one. Nil is the honest answer, and it
    /// leaves the caller — which already holds the verified account and its name
    /// — to fall back without a read that only repeats what it has.
    func accountNickname(in chatRoom: ChatRoom) async -> String? { nil }

    /// A source that remembers nothing has nothing to forget.
    func forgetAccountNickname() async {}

    /// A source with no view of KakaoTalk's own list says so.
    func joinedRoomNames() async -> Set<String>? { nil }

    func openRoomWindowNames() async -> Set<String>? { nil }
}
