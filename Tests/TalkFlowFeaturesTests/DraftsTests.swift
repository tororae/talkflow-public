import Foundation
import Testing
import TalkFlowApplication
import TalkFlowDomain
@testable import TalkFlowFeatures

private let room = ChatRoom(id: "room-g", displayName: "달빛 스튜디오", kind: .group)

private func roomEntry(_ responseMode: ResponseMode = .off) -> ChatRoomPolicy {
    ChatRoomPolicy(
        room: room,
        policy: RoomPolicy(
            accountFingerprint: "katok-test",
            chatRoomID: room.id,
            responseMode: responseMode
        )
    )
}

private func personEntry(note: String, links: [PersonLink] = []) -> PersonEntry {
    PersonEntry(
        note: PersonNote(
            chatRoomID: room.id,
            senderID: "sender-1",
            displayName: "왕만두",
            note: note,
            links: links,
            updatedAt: Date(timeIntervalSince1970: 0)
        ),
        room: room
    )
}

/// Nothing typed means nothing pending: the screen reads what is on disk through
/// the same call it reads an edit through, so a row with no draft cannot draw
/// blank.
@Test
func aRowWithNoEditReadsWhatIsOnDisk() {
    let drafts = RoomPolicyDrafts()
    let entry = roomEntry(.mentionOnly)

    #expect(drafts.draft(for: entry).responseMode == .mentionOnly)
    #expect(!drafts.has(entry))
    #expect(drafts.editedIDs.isEmpty)
}

@Test
func anEditIsHeldAndMarkedWithoutBeingWritten() {
    var drafts = RoomPolicyDrafts()
    let entry = roomEntry(.off)

    drafts.edit(entry) { $0.responseMode = .automatic }

    #expect(drafts.draft(for: entry).responseMode == .automatic)
    #expect(drafts.has(entry))
    #expect(drafts.editedIDs == [entry.id])
    // What was passed in is untouched: the screen's copy of disk stays disk.
    #expect(entry.policy.responseMode == .off)
}

/// An edit that lands back on the stored value is not an edit. Without this,
/// moving a picker away and back would leave 저장 lit with nothing to save, which
/// teaches the user to ignore it.
@Test
func movingAPickerAwayAndBackLeavesNothingToSave() {
    var drafts = RoomPolicyDrafts()
    let entry = roomEntry(.off)

    drafts.edit(entry) { $0.responseMode = .automatic }
    drafts.edit(entry) { $0.responseMode = .off }

    #expect(!drafts.has(entry))
    #expect(drafts.editedIDs.isEmpty)
}

@Test
func discardingPutsBackWhatIsOnDisk() {
    var drafts = RoomPolicyDrafts()
    let entry = roomEntry(.off)

    drafts.edit(entry) { $0.responseMode = .automatic }
    drafts.discard(entry)

    #expect(drafts.draft(for: entry).responseMode == .off)
    #expect(!drafts.has(entry))
}

/// Two rows, one holding an edit. Opening the other to check something must not
/// throw away what was typed in the first, and must not show it there either.
@Test
func anEditOnOneRowLeavesTheOtherRowsAlone() {
    var drafts = PersonNoteDrafts()
    let edited = personEntry(note: "예전 메모")
    let untouched = PersonEntry(
        note: PersonNote(
            chatRoomID: room.id,
            senderID: "sender-2",
            displayName: "다른 사람",
            note: "건드리지 않은 메모",
            updatedAt: Date(timeIntervalSince1970: 0)
        ),
        room: room
    )

    drafts.edit(edited) { $0.note = "고치는 중" }

    #expect(drafts.draft(for: edited).note == "고치는 중")
    #expect(drafts.draft(for: untouched).note == "건드리지 않은 메모")
    #expect(drafts.editedIDs == [edited.id])
}

/// The reason a person's draft is compared as a `PersonNoteDraft` and not as the
/// `PersonNote` on disk. Past the character limit the stored note has already been
/// cut, so a draft holding the whole sentence has to keep reading as pending —
/// otherwise 저장 would go dark on the one edit that most needs saving, and what
/// was typed past 300 characters would be gone with nothing said about it.
@Test
func aNoteTypedPastTheStoredLimitStillReadsAsPending() {
    var drafts = PersonNoteDrafts()
    let entry = personEntry(note: String(repeating: "가", count: PersonNote.characterLimit))
    let tooLong = String(repeating: "가", count: PersonNote.characterLimit + 20)

    drafts.edit(entry) { $0.note = tooLong }

    #expect(drafts.has(entry))
    #expect(drafts.draft(for: entry).note == tooLong)
}
