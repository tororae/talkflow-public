import Foundation
import TalkFlowDomain

/// The commands that list what the account has: rooms, and the people TalkFlow
/// has collected 사람 기억 on inside one of them.
///
/// The reads under them are only ever read from here — a room number is the
/// shared one, but a policy lookup, a note listing and a reply count are what
/// these four commands print and nothing else does.
extension HandleAdminCommand {
    // MARK: - !방 · !방 <검색>

    func roomsResponse(filter: String?, sorted: [ChatRoom], account: AccountProfile) async -> String {
        let policies = (try? await policyStore.policies(accountFingerprint: account.fingerprint)) ?? [:]
        // The number is the global index, assigned before any filter, so a search
        // is only ever a way to *find* a room — its number is still the one `!방`
        // would have shown and `!방 <N>` will answer to.
        let numbered = sorted.enumerated().map { index, room in
            AdminCommandResponder.NumberedRoom(
                number: index + 1,
                room: room,
                policy: policy(for: room, in: policies, account: account)
            )
        }
        let matched: [AdminCommandResponder.NumberedRoom]
        if let filter, !filter.isEmpty {
            matched = numbered.filter { $0.room.displayName.localizedCaseInsensitiveContains(filter) }
        } else {
            matched = numbered
        }
        return AdminCommandResponder.rooms(
            shown: Array(matched.prefix(AdminCommandResponder.roomsDisplayCap)),
            matched: matched.count,
            total: sorted.count,
            filter: filter
        )
    }

    // MARK: - !방 <N>

    func roomResponse(number: Int, sorted: [ChatRoom], account: AccountProfile) async -> String {
        guard let room = room(atNumber: number, in: sorted) else { return AdminCommandResponder.unknownRoom }
        let policy = (try? await policyStore.policy(for: room, accountFingerprint: account.fingerprint))
            ?? .makeDefault(accountFingerprint: account.fingerprint, room: room)
        // Live window state, read once for this one room. Nil when KakaoTalk's
        // list could not be read at all, which the formatter leaves off rather
        // than drawing 닫힘 over a window it never saw.
        let windowOpen = await connection.openRoomWindowNames().map { $0.contains(room.displayName) }
        return AdminCommandResponder.room(
            AdminCommandResponder.NumberedRoom(number: number, room: room, policy: policy),
            windowOpen: windowOpen
        )
    }

    // MARK: - !유저 · !유저 <N>

    func usersResponse(
        roomNumber: Int?,
        consoleRoom: ChatRoom,
        sorted: [ChatRoom],
        account: AccountProfile
    ) async -> String {
        let target: ChatRoom
        let number: Int
        if let roomNumber {
            guard let room = room(atNumber: roomNumber, in: sorted) else { return AdminCommandResponder.unknownRoom }
            target = room
            number = roomNumber
        } else {
            // No number is the console room itself, printed with its own global
            // number so the header reads like every other room's.
            target = consoleRoom
            number = (sorted.firstIndex { $0.id == consoleRoom.id } ?? 0) + 1
        }

        let policy = (try? await policyStore.policy(for: target, accountFingerprint: account.fingerprint))
            ?? .makeDefault(accountFingerprint: account.fingerprint, room: target)
        let notes = await collectedPeople(in: target, account: account)
        let counts = await replyCounts(in: target, account: account)

        let members = notes.enumerated().map { index, note in
            AdminCommandResponder.NumberedMember(
                number: index + 1,
                displayName: note.displayName,
                replyCount: counts[note.senderID] ?? 0,
                noteSummary: Self.summary(of: note.note)
            )
        }

        return AdminCommandResponder.people(
            roomNumber: number,
            roomName: target.displayName,
            remembersPeople: policy.remembersPeople,
            members: members
        )
    }

    // MARK: - !유저 <N> <M>

    func memberResponse(
        roomNumber: Int,
        memberNumber: Int,
        sorted: [ChatRoom],
        account: AccountProfile
    ) async -> String {
        guard let target = room(atNumber: roomNumber, in: sorted) else { return AdminCommandResponder.unknownRoom }
        let notes = await collectedPeople(in: target, account: account)
        guard memberNumber >= 1, memberNumber <= notes.count else { return AdminCommandResponder.unknownMember }
        let note = notes[memberNumber - 1]
        let counts = await replyCounts(in: target, account: account)

        return AdminCommandResponder.person(
            roomName: target.displayName,
            displayName: note.displayName,
            replyCount: counts[note.senderID] ?? 0,
            note: note.note,
            links: note.links
        )
    }

    private func policy(
        for room: ChatRoom,
        in policies: [String: RoomPolicy],
        account: AccountProfile
    ) -> RoomPolicy {
        policies[room.id] ?? .makeDefault(accountFingerprint: account.fingerprint, room: room)
    }

    /// The people TalkFlow has collected 사람 기억 on in this room — the notes it
    /// actually wrote, not everyone who spoke. Sorted by name (ties broken by the
    /// sender id KakaoTalk stamps) so the same number means the same person on the
    /// next command without anything kept between them.
    private func collectedPeople(in room: ChatRoom, account: AccountProfile) async -> [PersonNote] {
        guard let store = personNotes,
              let notes = try? await store.notes(inRoom: room.id, accountFingerprint: account.fingerprint)
        else {
            return []
        }
        return notes.sorted {
            switch $0.displayName.localizedStandardCompare($1.displayName) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return $0.senderID < $1.senderID
            }
        }
    }

    /// The first line of a note, shortened for a list row.
    private static func summary(of note: String) -> String {
        let firstLine = note.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        return trimmed.count > 24 ? String(trimmed.prefix(24)) + "…" : trimmed
    }

    private func replyCounts(in room: ChatRoom, account: AccountProfile) async -> [String: Int] {
        guard let rows = try? await actionLog.replyCountsBySender(
            chatRoomID: room.id,
            accountFingerprint: account.fingerprint
        ) else {
            return [:]
        }
        return rows.reduce(into: [:]) { $0[$1.senderID] = $1.count }
    }
}
