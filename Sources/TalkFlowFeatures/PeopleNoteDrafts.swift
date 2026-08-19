import TalkFlowDomain

/// One person's note as it is being typed: the prose and the links, and nothing
/// else the stored note carries.
///
/// Held as plain text rather than as a `PersonNote` on purpose. That value type
/// trims the note to its character limit and the links to five as it is built, so
/// a draft kept in one would quietly shorten what somebody was still typing and
/// the field would lose the end of their sentence mid-word. The limits belong at
/// 저장, where they can be refused out loud.
public struct PersonNoteDraft: Equatable, Sendable {
    public var note: String
    public var links: [PersonLink]

    public init(_ note: PersonNote) {
        self.note = note.note
        links = note.links
    }
}

/// Person notes edited but not yet written, one pending copy per person.
///
/// The 사람 screen's half of `Drafts`, which is where the bargain 저장 and 취소
/// make is written down. What differs from the room screen is the comparison: a
/// note is compared as a `PersonNoteDraft` rather than as the `PersonNote` on
/// disk, for the reason above — the stored note has already been trimmed, so
/// comparing against it would call a draft "changed" the moment somebody typed
/// past the limit and never call it unchanged again.
///
/// The key is `PersonEntry.id` — room and sender — so editing a person in one room
/// leaves the same person's note in another room alone.
typealias PersonNoteDrafts = Drafts<PersonEntry>

extension PersonEntry: DraftableEntry {
    var savedValue: PersonNoteDraft { PersonNoteDraft(note) }
}
