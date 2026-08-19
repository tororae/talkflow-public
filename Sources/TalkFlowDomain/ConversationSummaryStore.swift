import Foundation

/// Where a room's standing note lives.
///
/// Its own port rather than a pair of methods on `RoomPolicyStore`, because the
/// two have different writers on different schedules. A policy is written by the
/// room screen, on every keystroke of 답변 조건, as a full-row upsert that names
/// every column. A summary is written by a background sweep that may be in flight
/// while the user is flipping switches, and the two writers sharing a row would
/// have each quietly undo the other's read-modify-write.
///
/// Deleting is a first-class operation for the same reason it is a button on the
/// screen: this is a written description of real people, and "지우기" has to mean
/// the row is gone rather than four columns set to something that every later
/// reader has to agree to interpret as absence.
public protocol ConversationSummaryStore: Sendable {
    func summary(for room: ChatRoom, accountFingerprint: String) async throws -> ConversationSummary?
    /// Every room's note in one read, for a sweep that would otherwise ask the
    /// same question once per room on every turn.
    func summaries(accountFingerprint: String) async throws -> [String: ConversationSummary]
    func save(_ summary: ConversationSummary) async throws
    func clear(chatRoomID: String, accountFingerprint: String) async throws
}
