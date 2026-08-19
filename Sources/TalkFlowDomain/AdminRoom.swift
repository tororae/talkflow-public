/// Which rooms this account has designated as admin consoles.
///
/// A separate port from `RoomPolicyStore` on purpose: an admin room is not a way
/// a room *answers*, it is a room the operator drives the app from. Bundling it
/// into the policy would put a meta-control among the reply settings and make the
/// room editor carry a switch that has nothing to do with how that room behaves.
///
/// Keyed per account and per room, like a hidden room, and off for everybody
/// until it is explicitly turned on in 설정 — a room becomes a command console
/// because somebody said so, never by default and never by an upgrade.
public protocol AdminRoomStore: Sendable {
    func adminRoomIDs(accountFingerprint: String) async throws -> Set<String>
    func setAdminRoom(_ isAdmin: Bool, chatRoomID: String, accountFingerprint: String) async throws
}
