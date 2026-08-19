import Foundation
import TalkFlowDomain

/// 활동 as the console prints it: one numbered page of what the app did, and
/// one row in full.
///
/// The paging, the filter both commands read against, and the shortening the
/// two of them need are here together because the numbers only line up while
/// the list and the detail read the same rows in the same order.
extension HandleAdminCommand {
    // MARK: - !활동

    private static let activityPageSize = 10

    /// One page of recent bot activity, numbered globally (newest = 1). All rooms,
    /// or one when numbered. 관리자 명령 rows are left out — an operator does not want
    /// their own commands filling the list.
    func activityResponse(roomNumber: Int?, page: Int, sorted: [ChatRoom], account: AccountProfile) async -> String {
        let room: ChatRoom?
        if let roomNumber {
            guard let found = self.room(atNumber: roomNumber, in: sorted) else { return AdminCommandResponder.unknownRoom }
            room = found
        } else {
            room = nil
        }
        let page = max(page, 1)
        // Enough to fill this page and see whether another follows, with a buffer
        // for the 관리자 명령/other-account rows the filter drops.
        let filtered = await recentActions(roomID: room?.id, limit: page * Self.activityPageSize + 40, account: account)
        let start = (page - 1) * Self.activityPageSize
        let window = Array(filtered.dropFirst(start).prefix(Self.activityPageSize))
        let lines = window.enumerated().map { offset, action in
            AdminCommandResponder.ActivityLine(
                number: start + offset + 1,
                roomName: action.chatRoomName.isEmpty ? action.chatRoomID : action.chatRoomName,
                kind: action.kind.title,
                snippet: Self.snippet(of: action)
            )
        }
        return AdminCommandResponder.activity(
            roomNumber: roomNumber,
            roomName: room?.displayName,
            page: page,
            lines: lines,
            hasMore: filtered.count > start + window.count
        )
    }

    /// One action in full — the Mth newest in room N.
    func activityDetailResponse(roomNumber: Int, itemNumber: Int, sorted: [ChatRoom], account: AccountProfile) async -> String {
        guard let room = room(atNumber: roomNumber, in: sorted) else { return AdminCommandResponder.unknownRoom }
        guard itemNumber >= 1 else { return AdminCommandResponder.unknownActivity }
        let filtered = await recentActions(roomID: room.id, limit: itemNumber + 40, account: account)
        guard itemNumber <= filtered.count else { return AdminCommandResponder.unknownActivity }
        let action = filtered[itemNumber - 1]
        return AdminCommandResponder.activityDetail(
            roomNumber: roomNumber,
            detail: AdminCommandResponder.ActivityDetail(
                number: itemNumber,
                roomName: room.displayName,
                kind: action.kind.title,
                time: Self.activityTime(action.createdAt),
                reply: Self.detailText(action.replyText),
                answered: Self.detailText(action.triggerText)
            )
        )
    }

    /// Recent actions for a room (or all), this account only and 관리자 명령 dropped —
    /// the one filter both the list and the detail read against.
    private func recentActions(roomID: String?, limit: Int, account: AccountProfile) async -> [AgentAction] {
        let fetched: [AgentAction]
        if let roomID {
            fetched = (try? await actionLog.recent(chatRoomID: roomID, limit: limit)) ?? []
        } else {
            fetched = (try? await actionLog.recent(limit: limit)) ?? []
        }
        return fetched.filter { $0.accountFingerprint == account.fingerprint && $0.kind != .commanded }
    }

    /// The first line of what a row said or answered, shortened for one list line.
    private static func snippet(of action: AgentAction) -> String {
        let text = action.replyText ?? action.triggerText ?? ""
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        return trimmed.count > 24 ? String(trimmed.prefix(24)) + "…" : trimmed
    }

    /// Fuller than a list snippet but still bounded — the detail view's one line of
    /// what was said or answered.
    private static func detailText(_ text: String?) -> String {
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 200 ? String(trimmed.prefix(200)) + "…" : trimmed
    }

    private static func activityTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 HH:mm"
        return formatter.string(from: date)
    }
}
