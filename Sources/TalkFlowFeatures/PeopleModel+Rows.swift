import TalkFlowDomain

/// What the 사람 list and its detail pane read: the filter, the search, the
/// picker's rooms, and the one line under the table. Every one of them is
/// derived from `people`, so none of them can disagree with the rows.
@MainActor
extension PeopleModel {
    // MARK: - 목록

    /// The rows the list draws: the room filter, then the search box, over the
    /// people who have a note.
    ///
    /// The search reads the note itself and the sender id as well as the name.
    /// The name is what a user starts from, the note is what they remember when
    /// the name has gone ("그 파이프라인 하던 사람"), and the id is what the row
    /// itself offers them when two people share a name.
    public var entries: [PersonEntry] {
        let visible = roomFilterID.map { roomID in
            people.filter { $0.room.id == roomID }
        } ?? people
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return visible }
        return visible.filter {
            $0.note.displayName.localizedCaseInsensitiveContains(query)
                || $0.note.note.localizedCaseInsensitiveContains(query)
                || $0.note.senderID.contains(query)
        }
    }

    /// The rooms the picker offers, which is not every room the account has.
    ///
    /// 사람 기억 ships off in every room, and the account this was designed
    /// against carries 234 rooms; a picker listing all of them would be two
    /// hundred entries that filter to nothing hiding the handful that do not. Only rooms somebody was actually
    /// found in are offered, hidden ones included — a room hidden from 채팅방 is a
    /// room the user stopped configuring, not a person they stopped knowing.
    public var filterRooms: [ChatRoom] {
        var seen: Set<String> = []
        var rooms: [ChatRoom] = []
        for entry in people where seen.insert(entry.room.id).inserted {
            rooms.append(entry.room)
        }
        return rooms.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    /// Looked up in `people` and not in `entries`, so narrowing the list to a room
    /// does not close the note being read. Selecting a row is a statement about
    /// what is being read; the picker above is a statement about what is easy to
    /// find.
    public var selectedEntry: PersonEntry? {
        guard let selectedEntryID else { return nil }
        return people.first { $0.id == selectedEntryID }
    }

    /// Notes and not people, because that is what the list holds. Saying 「사람
    /// N명」 over rows that can name the same person twice would be a count nobody
    /// could reconcile with what they are looking at.
    public var summary: String {
        switch state {
        case .idle, .loading:
            return "사람 메모를 불러오는 중입니다."
        case .loaded:
            return "사람 메모 \(people.count)개 · 메모가 있는 방 \(filterRooms.count)곳"
        case let .failed(reason):
            return reason
        }
    }
}
