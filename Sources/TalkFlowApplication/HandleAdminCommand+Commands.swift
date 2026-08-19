import Foundation
import TalkFlowDomain

/// The half that reads the ports each command needs and hands plain data to the
/// formatter. Split from the flow in `HandleAdminCommand` so that "what a command
/// looks up" and "when a command is allowed to run" stay separate questions.
extension HandleAdminCommand {
    /// Runs one parsed command against the account's rooms and returns the text to
    /// send back. Never throws: a port that cannot be read degrades to a listing
    /// with default values rather than a console that answers an error.
    func respond(
        to command: AdminCommand,
        consoleRoom: ChatRoom,
        sorted: [ChatRoom],
        account: AccountProfile
    ) async -> String {
        switch command {
        case .help:
            return AdminCommandResponder.help()
        case let .rooms(filter):
            return await roomsResponse(filter: filter, sorted: sorted, account: account)
        case let .room(number):
            return await roomResponse(number: number, sorted: sorted, account: account)
        case let .users(roomNumber):
            return await usersResponse(roomNumber: roomNumber, consoleRoom: consoleRoom, sorted: sorted, account: account)
        case let .member(roomNumber, memberNumber):
            return await memberResponse(roomNumber: roomNumber, memberNumber: memberNumber, sorted: sorted, account: account)
        case .settingUsage:
            return AdminCommandResponder.settingUsage()
        case let .settingFields(roomNumber):
            return await settingFieldsResponse(roomNumber: roomNumber, sorted: sorted, account: account)
        case let .settingField(roomNumber, field):
            return await settingFieldResponse(roomNumber: roomNumber, field: field, sorted: sorted, account: account)
        case let .setting(roomNumber, field, value):
            return await settingResponse(roomNumber: roomNumber, field: field, value: value, sorted: sorted, account: account)
        case let .toggleRoom(roomNumber, on):
            return await toggleRoomResponse(roomNumber: roomNumber, on: on, sorted: sorted, account: account)
        case let .activity(roomNumber, page):
            return await activityResponse(roomNumber: roomNumber, page: page, sorted: sorted, account: account)
        case let .activityDetail(roomNumber, itemNumber):
            return await activityDetailResponse(roomNumber: roomNumber, itemNumber: itemNumber, sorted: sorted, account: account)
        case let .presetApply(roomNumber, name):
            return await presetApplyResponse(roomNumber: roomNumber, name: name, sorted: sorted, account: account)
        case let .presetList(roomNumber):
            return presetListResponse(roomNumber: roomNumber, sorted: sorted)
        }
    }

    // MARK: - shared reads

    /// 1-based, matching how the commands address a room. Out of range is nil, so
    /// the caller answers 「그런 번호의 방이 없어요」 rather than trapping.
    func room(atNumber number: Int, in sorted: [ChatRoom]) -> ChatRoom? {
        guard number >= 1, number <= sorted.count else { return nil }
        return sorted[number - 1]
    }
}
