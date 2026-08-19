import Foundation

/// Where a room is in its 집중 시간 cycle, kept because the cycle outlives a
/// judgement and outlives the app.
///
/// On disk rather than in memory, and the reason is the cooldown rather than the
/// burn. A burn that vanished on restart would cost the room a few minutes of
/// being talkative; a cooldown that vanished would let a room burn again the
/// moment the app came back, which is the one thing the cooldown exists to stop.
public protocol BurningStateStore: Sendable {
    func state(for chatRoomID: String, accountFingerprint: String) async throws -> BurningState?
    func save(
        _ state: BurningState,
        for chatRoomID: String,
        accountFingerprint: String
    ) async throws
    /// When the end of the current burn was last spoken about in this room.
    ///
    /// Recorded separately from the state itself, because it happens later and
    /// for a different reason: the state is written when a burn starts, and this
    /// when the room is told the burn is over. Writing the whole state again to
    /// carry one instant would mean re-writing a drawn deadline, which is how a
    /// live burn ends up with a new end time.
    func markAnnounced(
        at instant: Date,
        for chatRoomID: String,
        accountFingerprint: String
    ) async throws
    func announcedAt(for chatRoomID: String, accountFingerprint: String) async throws -> Date?

    /// Whether 답변 활성화 시간 was open when this room was last looked at, or nil
    /// for a room never looked at before.
    ///
    /// Here rather than in a store of its own because it answers the same
    /// question the rest of this protocol does — where is this room right now,
    /// as opposed to how was it configured. Nil is not "closed": a room seen for
    /// the first time has not crossed anything, and reading nil as closed would
    /// greet every room once on the first sync after an upgrade.
    func hoursWereOpen(for chatRoomID: String, accountFingerprint: String) async throws -> Bool?
    func recordHoursOpen(
        _ isOpen: Bool,
        for chatRoomID: String,
        accountFingerprint: String
    ) async throws
}
