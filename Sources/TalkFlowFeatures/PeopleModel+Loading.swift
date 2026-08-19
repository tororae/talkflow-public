import TalkFlowApplication
import TalkFlowDomain

/// Reading every room's notes and turning them into rows.
///
/// `setPeople` lives here rather than beside 저장 because it is the tail of a
/// load: it is where the id tails that tell two people with one name apart are
/// worked out, and every write goes back through it for exactly that reason.
@MainActor
extension PeopleModel {
    public func loadIfNeeded() async {
        if case .loaded = state { return }
        await reload()
    }

    /// Reads again unless a read is already in flight, and keeps what is on
    /// screen while it does.
    ///
    /// Every other screen in this app can load once and be right: a room's
    /// settings change only when somebody changes them, and this model's own
    /// `loadIfNeeded` was written on that assumption. Notes are the exception —
    /// they are written by the 채팅방 요약 sweep, in the background, with nobody
    /// looking. A tab that read once showed whatever existed the first time it
    /// was opened and never caught up, which is what a person reads as the
    /// feature not working.
    ///
    /// Not `reload`, because that clears to `.loading` and empties the table on
    /// every visit. The list is nearly always the same list, and blanking it to
    /// re-draw the same rows is a flicker on every tab switch.
    public func refreshQuietly() async {
        if case .loading = state { return }
        await reload(showingProgress: false)
    }

    /// Reads every room's notes, in one pass, and keeps them all.
    ///
    /// Per room because that is what a note is scoped to. Every room rather than
    /// only the one being filtered by, so the picker can offer rooms that have
    /// notes and the filter can move without a reload.
    public func reload() async {
        await reload(showingProgress: true)
    }

    private func reload(showingProgress: Bool) async {
        guard let notes else {
            state = .failed("메모를 저장할 곳을 열지 못했습니다. 사람 기억은 이 Mac의 데이터베이스에 저장됩니다.")
            return
        }

        if showingProgress { state = .loading }
        await roomList.loadIfNeeded()
        let board: RoomPolicyBoard
        switch roomList.state {
        case let .loaded(loaded):
            board = loaded
        case let .failed(reason):
            state = .failed(reason)
            return
        case .idle, .loading:
            state = .failed("채팅방 목록을 아직 불러오지 못했습니다.")
            return
        }

        var found: [(note: PersonNote, room: ChatRoom)] = []
        for entry in board.entries {
            let inRoom: [PersonNote]
            do {
                inRoom = try await notes.notes(
                    inRoom: entry.room.id,
                    accountFingerprint: board.accountFingerprint
                )
            } catch {
                // The whole load fails rather than the rooms that answered being
                // shown. A person quietly missing from this list reads as a person
                // TalkFlow has written nothing about, which is the one wrong thing
                // this screen must never say.
                state = .failed(error.localizedDescription)
                return
            }
            // No merging by sender. Two rooms answering with the same person are
            // two notes, and collapsing them here is what the room in the key
            // exists to prevent.
            found.append(contentsOf: inRoom.map { (note: $0, room: entry.room) })
        }

        setPeople(found)
        state = .loaded
    }

    /// The one place `people` is written, so the marks that tell two people with
    /// one name apart are recomputed every time the list changes rather than at
    /// load only. Deleting one of a name-sharing pair leaves the other with a
    /// name that is now unique, and an id tail still hanging off it would be an
    /// answer to a question nobody is asking any more.
    func setPeople(_ found: [(note: PersonNote, room: ChatRoom)]) {
        // Tails are worked out one room at a time. Across rooms the room name on
        // the row already separates two rows that share a name, and an id hung off
        // both of those would be a mark answering a question the row has already
        // answered.
        var tails: [String: String] = [:]
        for (_, sharing) in Dictionary(grouping: found, by: { $0.note.chatRoomID }) {
            for (senderID, tail) in Self.idTails(for: sharing.map(\.note)) {
                tails["\(sharing[0].note.chatRoomID)\u{1}\(senderID)"] = tail
            }
        }

        people = found
            .map { person in
                PersonEntry(
                    note: person.note,
                    room: person.room,
                    idTail: tails["\(person.note.chatRoomID)\u{1}\(person.note.senderID)"]
                )
            }
            .sorted { left, right in
                let byName = left.note.displayName.localizedStandardCompare(right.note.displayName)
                guard byName == .orderedSame else { return byName == .orderedAscending }
                // Same name, so the room decides, then the id. It has to decide
                // something, or two rows reading the same name swap places between
                // loads.
                let byRoom = left.room.displayName.localizedStandardCompare(right.room.displayName)
                guard byRoom == .orderedSame else { return byRoom == .orderedAscending }
                return left.id < right.id
            }

        // Deleting the last note in a room takes that room out of the picker, and
        // a filter left pointing at it would leave the list empty with the picker
        // showing nothing to explain why.
        if let roomFilterID, !people.contains(where: { $0.room.id == roomFilterID }) {
            self.roomFilterID = nil
        }
    }

    /// Enough of the sender id to tell the people sharing a name apart, and
    /// nothing for anybody else.
    ///
    /// Grown until it separates them rather than fixed at some comfortable length.
    /// Four digits happened to separate the pair this was designed against, and
    /// would not separate two ids that ended alike. That failure is not
    /// cosmetic: it is two rows that look identical again, which is the bug this
    /// mark exists to prevent. Ids are unique, so the loop always terminates.
    private static func idTails(for notes: [PersonNote]) -> [String: String] {
        var tails: [String: String] = [:]
        let byName = Dictionary(grouping: notes) {
            $0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        for (_, sharing) in byName where sharing.count > 1 {
            let ids = sharing.map(\.senderID)
            let longest = ids.map(\.count).max() ?? 0
            var length = min(Self.shortestIDTail, longest)
            while length < longest, Set(ids.map { $0.suffix(length) }).count < ids.count {
                length += 1
            }
            for id in ids {
                tails[id] = String(id.suffix(length))
            }
        }
        return tails
    }

    /// Short enough to read as a mark beside a name rather than as a number the
    /// user is being asked to understand. It grows when it has to.
    private static let shortestIDTail = 4
}
