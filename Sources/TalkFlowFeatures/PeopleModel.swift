import Foundation
import Observation
import TalkFlowApplication
import TalkFlowDomain

/// The 사람 screen: who TalkFlow has written a note about, and what it says.
///
/// The room picker on this screen is a scope, and the rows say so. A note belongs
/// to one room, so the same person in two rooms is two rows with two notes that
/// can disagree — and should be able to, because a person in one room is not the
/// same correspondent as they are in another.
///
/// It read the other way until v24: one note per person, the picker a way of
/// finding somebody. That was argued for with room counts read off the logged-out
/// account (`PLATFORM-FINDINGS` §1.4).
///
/// Rooms come from `ChatRoomListModel` rather than from a load of its own. That
/// board is one process launch — the account has to be verified and KakaoTalk's
/// room list read — and the rooms this screen filters by must be exactly the rooms
/// 채팅방 lists, not a second reading of them that can disagree.
@MainActor
@Observable
public final class PeopleModel {
    public enum State: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    /// Deliberately the shape `ChatRoomListModel.RoomSaveStatus` has. Three
    /// screens that make the same 저장/취소 bargain should not each report it
    /// differently.
    public enum SaveStatus: Equatable {
        case idle
        case saving
        case saved
        case failed(String)
    }

    public internal(set) var state: State = .idle
    /// Every note, whatever the filter says. The filter reads from this; it never
    /// replaces it, which is how a note stays open after the room it was found
    /// under is filtered away.
    public internal(set) var people: [PersonEntry] = []
    public var searchText = ""
    /// Which room the list is narrowed to, nil for 모든 방.
    public var roomFilterID: String?
    /// A `PersonEntry.id` — room and sender — and not a sender id. The same person
    /// in two rooms is two selectable rows.
    public var selectedEntryID: String?
    public private(set) var saveStatus: SaveStatus = .idle
    /// Why 저장 refused. Kept apart from `saveStatus` because a refusal is not a
    /// failed write — nothing was attempted — and because the text has to survive
    /// on screen while the user fixes what it is complaining about.
    public private(set) var issue: String?

    /// Edits made but not yet written. See `PersonNoteDrafts`.
    private var drafts = PersonNoteDrafts()
    let roomList: ChatRoomListModel
    /// Nil without a database, exactly as `burningStore` is. Nothing here can be
    /// read or written then, and the screen says that instead of drawing an empty
    /// list that looks like nobody has been remembered.
    let notes: (any PersonNoteStore)?

    public init(roomList: ChatRoomListModel, notes: (any PersonNoteStore)?) {
        self.roomList = roomList
        self.notes = notes
    }

    // MARK: - 저장하지 않은 편집

    /// What the screen should show for a person: their pending edit if they have
    /// one, otherwise what is on disk.
    public func draft(for entry: PersonEntry) -> PersonNoteDraft {
        drafts.draft(for: entry)
    }

    public func hasUnsavedChanges(_ entry: PersonEntry) -> Bool {
        drafts.has(entry)
    }

    /// Which rows are holding edits, so the list can mark them. A pending change
    /// scrolled out of sight is a change the user will forget they made — the same
    /// reason the room list carries a dot.
    ///
    /// `PersonEntry.id`s, so an edit to somebody in one room does not mark the same
    /// person's row in another.
    public var unsavedEntryIDs: Set<String> {
        drafts.editedIDs
    }

    /// Records what was typed without writing it. The only way this screen edits a
    /// note.
    public func editNote(_ text: String, for entry: PersonEntry) {
        edit(entry) { $0.note = text }
    }

    public func editLink(_ link: PersonLink, at index: Int, for entry: PersonEntry) {
        edit(entry) { draft in
            guard draft.links.indices.contains(index) else { return }
            draft.links[index] = link
        }
    }

    /// Takes the two fields rather than appending a blank row for the user to fill
    /// in, which is how `KeywordListEditor` already works. A blank row is a row
    /// 저장 has to refuse, and a screen that answers 추가 with a complaint is one
    /// that made the user press the button to find out it was not allowed.
    ///
    /// Returns false when the link was refused, so the fields keep what was typed
    /// instead of swallowing it.
    @discardableResult
    public func addLink(label: String, url: String, for entry: PersonEntry) -> Bool {
        let address = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else {
            issue = "주소를 입력해 주세요."
            return false
        }

        // An unnamed link is drawn by its address, and doing that here rather than
        // in the row means what the list shows is what was stored.
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        edit(entry) { $0.links.append(PersonLink(label: name.isEmpty ? address : name, url: address)) }
        return true
    }

    public func removeLink(at index: Int, for entry: PersonEntry) {
        edit(entry) { draft in
            guard draft.links.indices.contains(index) else { return }
            draft.links.remove(at: index)
        }
    }

    private func edit(_ entry: PersonEntry, _ change: (inout PersonNoteDraft) -> Void) {
        drafts.edit(entry, change)
        saveStatus = .idle
        // The complaint goes with the keystroke that answers it. A refusal still
        // sitting there while the user retypes reads as a second refusal.
        issue = nil
    }

    /// Writes what was typed, and refuses rather than shortens.
    ///
    /// `PersonNote`'s initialiser trims to its own character limit, which is right
    /// for a note a model wrote and wrong for one a person typed: pressing 저장 on
    /// 320 characters would silently return 300 and the last sentence would be
    /// gone with nothing said about it. So the length is checked here,
    /// before a `PersonNote` exists to do the cutting, and the text stays on screen
    /// with the reason beside it.
    public func save(for entry: PersonEntry) async {
        guard let notes, drafts.has(entry) else { return }
        let draft = drafts.draft(for: entry)

        guard draft.note.count <= PersonNote.characterLimit else {
            issue = "\(PersonNote.characterLimit)자까지 적을 수 있습니다. 지금 \(draft.note.count)자입니다."
            return
        }
        guard !draft.links.contains(where: { $0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            issue = "주소가 비어 있는 링크가 있습니다. 주소를 채우거나 그 줄을 지워 주세요."
            return
        }

        issue = nil
        saveStatus = .saving

        let updated = PersonNote(
            chatRoomID: entry.note.chatRoomID,
            senderID: entry.note.senderID,
            displayName: entry.note.displayName,
            note: draft.note,
            links: draft.links,
            // Carried, not set. Typing is not a request to stop refreshing — 고정
            // is the checkbox under the field, and it used to be this line, which
            // meant fixing one name froze the person's note for good.
            isPinned: entry.note.isPinned,
            // Carried through untouched. It is where the last refresh got to, and
            // clearing it would send the next one over the whole history again to
            // arrive at what is already here.
            coveredThroughMessageID: entry.note.coveredThroughMessageID,
            updatedAt: Date()
        )

        do {
            try await notes.save(updated)
        } catch {
            saveStatus = .failed(error.localizedDescription)
            return
        }

        drafts.discard(entry)
        setPeople(people.map { person in
            person.id == entry.id
                ? (note: updated, room: person.room)
                : (note: person.note, room: person.room)
        })
        saveStatus = .saved
    }

    /// 고정, written the moment it is switched rather than on 저장.
    ///
    /// It has to be immediate. The sweep reads this flag to decide whether it may
    /// rewrite the note, and a pin sitting unsaved in a draft would not stop the
    /// refresh that arrives while the user is still reading the sentence they were
    /// protecting. It deliberately does not carry the typed draft with it — the
    /// text is 저장's business, and pinning a paragraph somebody is mid-way through
    /// rewriting would store half a thought.
    public func setPinned(_ pinned: Bool, for entry: PersonEntry) async {
        guard let notes, entry.note.isPinned != pinned else { return }
        var updated = entry.note
        updated.isPinned = pinned
        do {
            try await notes.save(updated)
        } catch {
            issue = error.localizedDescription
            return
        }
        issue = nil
        setPeople(people.map { person in
            person.id == entry.id
                ? (note: updated, room: person.room)
                : (note: person.note, room: person.room)
        })
    }

    /// Back to what is on disk, in one step. The counterpart to 저장, and the
    /// reason somebody can try rewriting a sentence about their friend without
    /// committing to it.
    public func revert(_ entry: PersonEntry) {
        drafts.discard(entry)
        saveStatus = .idle
        issue = nil
    }

    /// Forgets this note outright — the prose, the links, and the row.
    ///
    /// A real delete and not a hide, unlike a chat room. A room is in the list
    /// because a message arrived and there is nothing to remove; a note is
    /// something this app wrote about somebody, and a person asking it to forget
    /// their friend has to be able to make that true.
    ///
    /// One room's note. The same person in another room keeps theirs, which is why
    /// the editor's confirmation names the room rather than the person alone.
    public func delete(_ entry: PersonEntry) async {
        guard let notes else { return }
        do {
            try await notes.delete(
                inRoom: entry.note.chatRoomID,
                senderID: entry.note.senderID
            )
        } catch {
            saveStatus = .failed(error.localizedDescription)
            return
        }

        drafts.discard(entry)
        setPeople(
            people
                .filter { $0.id != entry.id }
                .map { (note: $0.note, room: $0.room) }
        )
        if selectedEntryID == entry.id { selectedEntryID = nil }
        saveStatus = .idle
        issue = nil
    }
}
