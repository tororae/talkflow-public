/// An editable row: how it names itself, and what is on disk for it expressed in
/// the form a draft holds.
///
/// `Draft` is a separate type from whatever the row stores because it is not
/// always the same type. A room's draft is its `RoomPolicy` unchanged; a person's
/// is the prose and the links pulled out of their `PersonNote`, because that value
/// type trims as it is built and a draft kept in one would shorten what somebody
/// is still typing. `savedValue` is that projection, so the one comparison that
/// decides whether an edit is still an edit is made in the same terms the field
/// is holding.
protocol DraftableEntry: Identifiable {
    associatedtype Draft: Equatable

    /// What is on disk for this row, as a draft would hold it. Compared against
    /// the pending copy, so it has to be the projection and not the stored value:
    /// `PersonNote("abc…") != "abc…"` in every way that matters here.
    var savedValue: Draft { get }
}

/// Edits made but not yet written, one pending copy per row.
///
/// Its own type because it is its own idea, and because the models that hold it
/// already do enough. Both screens that have it made the same bargain for the same
/// reason: every control on the room screen used to write to disk the instant it
/// moved and say nothing about it — fifteen settings, no 저장, no 취소 — so there
/// was no telling a change that had applied from one that had not, and no way back
/// from one made by accident. On the 사람 screen it would have been worse still,
/// because each keystroke would have been a write of a paragraph somebody was in
/// the middle of composing about a real person, with no way back to the sentence
/// they replaced.
///
/// Keyed by row rather than held one at a time: opening another room or another
/// person to check something must not throw away what was typed here. The lists
/// mark the rows that are holding edits, because a pending change out of sight is
/// one the user will forget they made.
struct Drafts<Entry: DraftableEntry> {
    private var pending: [Entry.ID: Entry.Draft] = [:]

    /// The rows holding an edit, for the list to mark.
    var editedIDs: Set<Entry.ID> { Set(pending.keys) }

    /// What the screen should show: the pending edit if there is one, otherwise
    /// what is on disk.
    func draft(for entry: Entry) -> Entry.Draft {
        pending[entry.id] ?? entry.savedValue
    }

    func has(_ entry: Entry) -> Bool {
        pending[entry.id] != nil
    }

    /// An edit that lands back on the stored value is not an edit. Without this,
    /// moving a picker away and back — or deleting a word and typing it again —
    /// would leave 저장 lit with nothing to save, which teaches the user to ignore
    /// it.
    mutating func edit(_ entry: Entry, _ change: (inout Entry.Draft) -> Void) {
        var draft = draft(for: entry)
        change(&draft)
        if draft == entry.savedValue {
            pending.removeValue(forKey: entry.id)
        } else {
            pending[entry.id] = draft
        }
    }

    mutating func discard(_ entry: Entry) {
        pending.removeValue(forKey: entry.id)
    }
}
