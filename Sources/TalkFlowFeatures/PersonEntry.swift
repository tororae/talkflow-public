import TalkFlowDomain

/// One remembered person **in one room**, as a list has to draw them.
///
/// The name alone is not enough to draw, and that is the whole reason this type
/// exists rather than the screen reading `PersonNote` directly. 졸린 하마, Mina
/// and 공지알림봇 are each two different people in this account's rooms, and two
/// rows reading Mina and Mina would be a list that cannot be used to pick one.
/// (닉네임은 지어낸 것이다. 실제로 그런 방이 있었다는 것만 사실이다.)
///
/// A row is a note and not a person. The same human in three rooms is three rows,
/// because it is three notes — see `PersonNote`.
public struct PersonEntry: Identifiable, Equatable, Sendable {
    public let note: PersonNote
    /// The one room this note is about. Not every room the person appears in:
    /// there is no note that spans rooms to draw.
    public let room: ChatRoom
    /// The tail of the sender id, and nil for everybody whose name is already
    /// unique *in their room*. Drawn only where it settles a question the name
    /// leaves open: an id beside every row is noise, and noise on every row is what
    /// stops the one row that needed it from being read.
    ///
    /// Room-scoped because the room name on the row already separates two rows
    /// that share a name across rooms. Only a collision inside one room is left
    /// for the id to settle.
    public let idTail: String?

    /// The room and the sender together, which is the note's key. Keyed on the
    /// sender alone, the same person in two rooms would be one row and selecting
    /// either would open whichever loaded last.
    public var id: String { "\(note.chatRoomID)\u{1}\(note.senderID)" }

    public init(note: PersonNote, room: ChatRoom, idTail: String? = nil) {
        self.note = note
        self.room = room
        self.idTail = idTail
    }

    /// Which room this note is about, on the row. Load-bearing now rather than
    /// decorative: it is half of what identifies the row.
    public var roomLabel: String {
        room.displayName
    }

    /// The line the detail pane leads with, and the answer to the question the
    /// room picker above it invites: yes, the room scopes this note.
    public var roomScopeLabel: String {
        "\(room.displayName)에서의 메모"
    }
}
