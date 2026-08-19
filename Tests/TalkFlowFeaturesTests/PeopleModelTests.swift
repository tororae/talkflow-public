import Foundation
import Testing
import TalkFlowApplication
import TalkFlowDomain
@testable import TalkFlowFeatures

private let studio = ChatRoom(id: "room-studio", displayName: "달빛 스튜디오", kind: .group)
private let family = ChatRoom(id: "room-family", displayName: "가족", kind: .group)
private let quiet = ChatRoom(id: "room-quiet", displayName: "조용한 방", kind: .direct)

/// Two different people who share a nickname inside one room. Mina and 공지알림봇
/// are each two people in this account's rooms; these ids stand in for that case,
/// which is the one an id tail exists to settle. The ids are invented and carry
/// the shape of a real one — 19 digits, differing tails. See `PersonNote`.
private let oneWangmandu = "2703118845201730841"
private let otherWangmandu = "5471962330748126095"

/// Two people with one nickname must not draw as two identical rows. This is the
/// list being unusable in exactly the case the feature was designed around: a
/// user looking at 왕만두 and 왕만두 cannot pick the one they meant, and the
/// note they open is a coin toss.
@Test @MainActor
func twoPeopleWithOneNicknameAreDrawnApartAndNobodyElseIsMarked() async throws {
    let store = FakePersonNoteStore(
        [
            personNote(oneWangmandu, in: studio, name: "왕만두"),
            personNote(otherWangmandu, in: studio, name: "왕만두"),
            personNote("s-kang", in: studio, name: "강민석")
        ]
    )
    let model = makeModel(notes: store)
    await model.reload()

    let sharing = model.people.filter { $0.note.displayName == "왕만두" }
    #expect(sharing.count == 2)
    #expect(sharing.allSatisfy { $0.idTail != nil })
    #expect(Set(sharing.compactMap(\.idTail)).count == 2)
    // And the mark is not sprayed over everybody: an id beside every row is
    // noise, and noise on every row is what stops the row that needed it from
    // being read.
    #expect(try #require(model.people.first { $0.note.displayName == "강민석" }).idTail == nil)
}

/// The room picker is a scope, and one person in three rooms is three rows with
/// three notes that can disagree. A screen that merged them would be showing a
/// record the store does not have — and would let a sentence learned in 가족 arrive
/// in 달빛 스튜디오, which is what the room in the key exists to stop.
@Test @MainActor
func aPersonInSeveralRoomsIsOneRowPerRoomAndTheNotesDoNotMerge() async throws {
    let store = FakePersonNoteStore([
        personNote("s-kang", in: studio, name: "강민석", note: "배포 스크립트를 같이 봅니다."),
        personNote("s-kang", in: family, name: "강민석", note: "사촌 형입니다."),
        personNote("s-kang", in: quiet, name: "강민석", note: "서로 존댓말을 씁니다.")
    ])
    let model = makeModel(notes: store)
    await model.reload()

    #expect(model.people.count == 3)
    #expect(Set(model.people.map(\.id)).count == 3)
    #expect(Set(model.people.map(\.note.note)).count == 3)

    // Filtered to one room, one row, and it says which room it is speaking for.
    model.roomFilterID = family.id
    let inFamily = try #require(model.entries.first)
    #expect(model.entries.count == 1)
    #expect(inFamily.note.note == "사촌 형입니다.")
    #expect(inFamily.roomLabel == "가족")
    #expect(inFamily.roomScopeLabel == "가족에서의 메모")
}

/// Editing one room's note must not touch the same person's note elsewhere. This
/// is the property the whole change was made for, so it is asserted against the
/// store and not only against what is on screen.
@Test @MainActor
func savingOneRoomsNoteLeavesTheSamePersonsOtherRoomAlone() async throws {
    let store = FakePersonNoteStore([
        personNote("s-kang", in: studio, name: "강민석", note: "스튜디오 메모"),
        personNote("s-kang", in: family, name: "강민석", note: "가족 메모")
    ])
    let model = makeModel(notes: store)
    await model.reload()

    let inStudio = try #require(model.people.first { $0.room.id == studio.id })
    model.editNote("고쳐 쓴 스튜디오 메모", for: inStudio)
    await model.save(for: inStudio)

    #expect(store.saved(inRoom: studio.id, senderID: "s-kang")?.note == "고쳐 쓴 스튜디오 메모")
    #expect(store.saved(inRoom: family.id, senderID: "s-kang")?.note == "가족 메모")
    // And the pending-edit dot marked one row, not both.
    #expect(model.unsavedEntryIDs.isEmpty)
}

/// Deleting is per room too. 「이 사람을 잊어라」 in one room is not a statement
/// about every room they are in, and the editor's dialog says so — a delete that
/// quietly took all of them would be unrecoverable.
@Test @MainActor
func deletingOneRoomsNoteLeavesTheSamePersonsOtherRoomAlone() async throws {
    let store = FakePersonNoteStore([
        personNote("s-kang", in: studio, name: "강민석", note: "스튜디오 메모"),
        personNote("s-kang", in: family, name: "강민석", note: "가족 메모")
    ])
    let model = makeModel(notes: store)
    await model.reload()

    let inStudio = try #require(model.people.first { $0.room.id == studio.id })
    await model.delete(inStudio)

    #expect(store.saved(inRoom: studio.id, senderID: "s-kang") == nil)
    #expect(store.saved(inRoom: family.id, senderID: "s-kang")?.note == "가족 메모")
    #expect(model.people.map(\.id) == [entryID(family, "s-kang")])
}

/// Changing the filter must not close the note being read. The filter narrows what
/// is easy to find; what is open is a separate statement, and losing the pane
/// mid-edit would throw away what somebody was typing.
@Test @MainActor
func theOpenNoteStaysOpenWhenTheFilterMovesOffItsRoom() async throws {
    let store = FakePersonNoteStore([
        personNote("s-kang", in: studio, name: "강민석"),
        personNote("s-jisu", in: family, name: "지수")
    ])
    let model = makeModel(notes: store)
    await model.reload()

    model.selectedEntryID = entryID(studio, "s-kang")
    model.roomFilterID = family.id

    #expect(model.entries.map(\.id) == [entryID(family, "s-jisu")])
    #expect(model.selectedEntry?.id == entryID(studio, "s-kang"))
}

/// This account carries 234 rooms and 사람 기억 ships off in every one of them. A
/// picker listing every room would be two hundred entries that filter to nothing,
/// hiding the two that do not.
@Test @MainActor
func theRoomPickerOnlyOffersRoomsSomebodyWasFoundIn() async throws {
    let store = FakePersonNoteStore([personNote("s-kang", in: studio, name: "강민석")])
    let model = makeModel(notes: store)
    await model.reload()

    #expect(model.filterRooms.map(\.id) == [studio.id])
}

/// The note is a paragraph about a real person. Writing on every keystroke would
/// leave no way back to the sentence that was replaced, which is the bargain the
/// room screen already makes with 저장 and 취소.
@Test @MainActor
func typingInTheNoteIsHeldUntilSaved() async throws {
    let store = FakePersonNoteStore(
        [personNote("s-kang", in: studio, name: "강민석", note: "예전 메모")]
    )
    let model = makeModel(notes: store)
    await model.reload()
    let entry = try #require(model.people.first)

    model.editNote("대학 동기, 서로 반말", for: entry)

    #expect(model.hasUnsavedChanges(entry))
    #expect(model.unsavedEntryIDs == [entryID(studio, "s-kang")])
    #expect(store.saved(inRoom: studio.id, senderID: "s-kang")?.note == "예전 메모")

    await model.save(for: entry)

    #expect(store.saved(inRoom: studio.id, senderID: "s-kang")?.note == "대학 동기, 서로 반말")
    #expect(model.people.first?.note.note == "대학 동기, 서로 반말")
    #expect(!model.hasUnsavedChanges(try #require(model.people.first)))
    #expect(model.saveStatus == .saved)
}

/// The whole point of 취소: a sentence tried and thought better of leaves nothing
/// behind.
@Test @MainActor
func cancellingPutsTheNoteBackTheWayItWasOnDisk() async throws {
    let store = FakePersonNoteStore(
        [personNote("s-kang", in: studio, name: "강민석", note: "예전 메모")]
    )
    let model = makeModel(notes: store)
    await model.reload()
    let entry = try #require(model.people.first)

    model.editNote("고쳐 쓴 메모", for: entry)
    model.revert(entry)

    #expect(!model.hasUnsavedChanges(entry))
    #expect(model.draft(for: entry).note == "예전 메모")
    #expect(store.saved(inRoom: studio.id, senderID: "s-kang")?.note == "예전 메모")
}

/// `PersonNote` trims to its limit as it is built, so a save that handed the typed
/// text straight to it would return 300 characters and say nothing about the ones
/// it dropped. The user would find the end of their paragraph gone with no message
/// on the screen that took it.
@Test @MainActor
func aNoteOverTheLimitIsRefusedRatherThanQuietlyCutToFit() async throws {
    let store = FakePersonNoteStore(
        [personNote("s-kang", in: studio, name: "강민석", note: "예전 메모")]
    )
    let model = makeModel(notes: store)
    await model.reload()
    let entry = try #require(model.people.first)

    let tooLong = String(repeating: "가", count: PersonNote.characterLimit + 1)
    model.editNote(tooLong, for: entry)
    await model.save(for: entry)

    #expect(model.issue != nil)
    #expect(store.saved(inRoom: studio.id, senderID: "s-kang")?.note == "예전 메모")
    // Still on screen, and still unsaved, so the text can be fixed rather than
    // retyped.
    #expect(model.draft(for: entry).note == tooLong)
    #expect(model.hasUnsavedChanges(entry))
}

/// What a hand save must and must not touch. The refresh cursor has to survive —
/// clearing it sends the next sweep over the whole history to arrive at what is
/// already stored — and 고정 must not be set behind the user's back, which is the
/// thing this save used to do and had no way to undo.
@Test @MainActor
func savingByHandKeepsTheRefreshCursorAndDoesNotPin() async throws {
    let written = Date(timeIntervalSince1970: 1_000_000)
    let store = FakePersonNoteStore(
        [
            personNote(
                "s-kang",
                in: studio,
                name: "강민석",
                note: "예전 메모",
                coveredThrough: "m-42",
                updatedAt: written
            )
        ]
    )
    let model = makeModel(notes: store)
    await model.reload()
    let entry = try #require(model.people.first)

    model.editNote("대학 동기, 서로 반말", for: entry)
    await model.save(for: entry)

    let saved = try #require(store.saved(inRoom: studio.id, senderID: "s-kang"))
    // Saving does not claim the note. That is 고정's job, and inferring it from a
    // keystroke is what made a corrected person note unchangeable for good.
    #expect(!saved.isPinned)
    #expect(saved.coveredThroughMessageID == "m-42")
    #expect(saved.updatedAt > written)
    // The name is display and never the key, so a save must not move it.
    #expect(saved.senderID == "s-kang")
    #expect(saved.displayName == "강민석")
}

/// Nothing is dropped for being the sixth. The cap that remains is on how many
/// ride along on a reply, so a link past it is still kept, still shown and still
/// editable — it just does not go out on every message.
@Test @MainActor
func linksPastTheReplyCapAreKeptRatherThanRefused() async throws {
    let store = FakePersonNoteStore(
        [personNote("s-kang", in: studio, name: "강민석", links: (1...PersonNote.linksPerReply).map {
            PersonLink(label: "링크\($0)", url: "https://example.com/\($0)")
        })]
    )
    let model = makeModel(notes: store)
    await model.reload()
    let entry = try #require(model.people.first)

    #expect(model.addLink(label: "여섯", url: "https://example.com/6", for: entry))
    #expect(model.draft(for: entry).links.count == PersonNote.linksPerReply + 1)

    // And a row emptied in place is refused at 저장 rather than stored as a link
    // that points nowhere.
    model.editLink(PersonLink(label: "링크1", url: "  "), at: 0, for: entry)
    await model.save(for: entry)

    #expect(model.issue != nil)
    #expect(store.saved(inRoom: studio.id, senderID: "s-kang")?.links.first?.url == "https://example.com/1")
}

/// Deleting is the user asking TalkFlow to forget somebody, so the links go with
/// the prose and the row goes with both. The mark that told two 왕만두 apart
/// goes too: the name that is left is unique now, and an id tail hanging off it
/// would answer a question nobody is asking.
@Test @MainActor
func deletingForgetsThePersonAndTakesTheirDisambiguatingMarkWithThem() async throws {
    let store = FakePersonNoteStore(
        [
            personNote(oneWangmandu, in: studio, name: "왕만두", links: [PersonLink(label: "블로그", url: "https://example.com")]),
            personNote(otherWangmandu, in: studio, name: "왕만두")
        ]
    )
    let model = makeModel(notes: store)
    await model.reload()
    model.selectedEntryID = entryID(studio, oneWangmandu)
    let entry = try #require(model.people.first { $0.id == entryID(studio, oneWangmandu) })

    await model.delete(entry)

    #expect(store.saved(inRoom: studio.id, senderID: oneWangmandu) == nil)
    #expect(model.people.map(\.id) == [entryID(studio, otherWangmandu)])
    #expect(model.selectedEntryID == nil)
    #expect(model.people.first?.idTail == nil)
}

/// Deleting the last person in a room takes that room out of the picker, and a
/// filter left pointing at it would leave the list empty with the picker showing
/// nothing that explains why.
@Test @MainActor
func deletingTheLastPersonInARoomClearsAFilterThatPointedAtIt() async throws {
    let store = FakePersonNoteStore(
        [personNote("s-kang", in: studio, name: "강민석"), personNote("s-jisu", in: family, name: "지수")]
    )
    let model = makeModel(notes: store)
    await model.reload()
    model.roomFilterID = family.id
    let jisu = try #require(model.people.first { $0.id == entryID(family, "s-jisu") })

    await model.delete(jisu)

    #expect(model.roomFilterID == nil)
    #expect(model.filterRooms.map(\.id) == [studio.id])
    #expect(model.entries.map(\.id) == [entryID(studio, "s-kang")])
}

/// The row offers the tail of an id precisely when the name is ambiguous, so the
/// search box has to accept the thing the row just showed. Without this a user
/// reading 왕만두 …0841 has been given an identifier they cannot use.
@Test @MainActor
func searchFindsAPersonByTheIdTailTheirRowShows() async throws {
    let store = FakePersonNoteStore(
        [personNote(oneWangmandu, in: studio, name: "왕만두"), personNote(otherWangmandu, in: studio, name: "왕만두")]
    )
    let model = makeModel(notes: store)
    await model.reload()
    let tail = try #require(model.people.first { $0.id == entryID(studio, oneWangmandu) }?.idTail)

    model.searchText = tail

    #expect(model.entries.map(\.id) == [entryID(studio, oneWangmandu)])
}

/// Without a database there is nowhere to keep a note, and an empty list would
/// read as an account that has never remembered anybody. It says which of the two
/// it is.
@Test @MainActor
func withNoStoreTheScreenSaysSoInsteadOfShowingAnEmptyList() async throws {
    let model = makeModel(notes: nil)
    await model.reload()

    #expect(model.people.isEmpty)
    guard case let .failed(reason) = model.state else {
        Issue.record("저장소가 없을 때는 실패 상태여야 합니다.")
        return
    }
    #expect(!reason.isEmpty)
}

// MARK: - 준비

/// Remembers what the 사람 screen saved, so a test can read the store back instead
/// of trusting the model's own copy of what it thinks it wrote.
///
/// Membership is given per room rather than derived, because that is all the
/// screen asks of the store: the repository answers it out of the action log, and
/// what matters here is that one person can come back from several rooms.
///
/// A locked class rather than an actor because a test seeds it before the model
/// exists, where nothing can be awaited.
/// There is no separate membership map to seed. A note carries the room it is
/// about, so which room answers for whom is decided by the notes themselves — the
/// same thing the real store does now that the room is half the key.
final class FakePersonNoteStore: PersonNoteStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String: PersonNote] = [:]

    init(_ notes: [PersonNote] = []) {
        for note in notes {
            stored[Self.key(note.chatRoomID, note.senderID)] = note
        }
    }

    func saved(inRoom chatRoomID: String, senderID: String) -> PersonNote? {
        lock.withLock { stored[Self.key(chatRoomID, senderID)] }
    }

    func note(inRoom chatRoomID: String, senderID: String) async throws -> PersonNote? {
        saved(inRoom: chatRoomID, senderID: senderID)
    }

    func notes(inRoom chatRoomID: String, accountFingerprint: String) async throws -> [PersonNote] {
        lock.withLock {
            stored.values.filter { $0.chatRoomID == chatRoomID }
        }
    }

    func save(_ note: PersonNote) async throws {
        lock.withLock { stored[Self.key(note.chatRoomID, note.senderID)] = note }
    }

    func delete(inRoom chatRoomID: String, senderID: String) async throws {
        lock.withLock { stored[Self.key(chatRoomID, senderID)] = nil }
    }

    private static func key(_ chatRoomID: String, _ senderID: String) -> String {
        "\(chatRoomID)\u{1}\(senderID)"
    }
}

private func personNote(
    _ senderID: String,
    in room: ChatRoom,
    name: String,
    note: String = "같이 일하는 사람입니다.",
    links: [PersonLink] = [],
    isPinned: Bool = false,
    coveredThrough: String? = nil,
    updatedAt: Date = Date(timeIntervalSince1970: 1_000_000)
) -> PersonNote {
    PersonNote(
        chatRoomID: room.id,
        senderID: senderID,
        displayName: name,
        note: note,
        links: links,
        isPinned: isPinned,
        coveredThroughMessageID: coveredThrough,
        updatedAt: updatedAt
    )
}

/// A row's id, which is the room and the sender together.
private func entryID(_ room: ChatRoom, _ senderID: String) -> String {
    "\(room.id)\u{1}\(senderID)"
}

@MainActor
private func makeModel(
    rooms: [ChatRoom] = [studio, family, quiet],
    notes: FakePersonNoteStore?
) -> PeopleModel {
    let connection = FakeKakaoConnection(rooms: rooms)
    let policyStore = FakeRoomPolicyStore()
    let settings = FakeSettingsStore()
    let roomList = ChatRoomListModel(
        loadRooms: LoadRoomsWithPolicies(
            connection: connection,
            policyStore: policyStore,
            settingsStore: settings
        ),
        saveRoomPolicy: SaveRoomPolicy(policyStore: policyStore),
        readRoomPolicy: ReadRoomPolicy(policyStore: policyStore),
        hideRoom: HideChatRoom(policyStore: policyStore),
        inspectCalls: InspectRecentCalls(connection: connection),
        inspectPresence: InspectRoomPresence(connection: connection),
        inspectCycle: InspectJudgementCycle(actionLog: FakeJudgementLog())
    )
    return PeopleModel(roomList: roomList, notes: notes)
}

/// Every edit rebuilds the whole link, so a field the row does not draw has to be
/// carried across by hand — and was not. Editing a label reset 출처 to 모름, which
/// is a claim about whose work something is, silently reversed by renaming it.
@Test @MainActor
func renamingALinkKeepsWhoseWorkItIs() async throws {
    let store = FakePersonNoteStore(
        [personNote("s-kang", in: studio, name: "강민석", links: [
            PersonLink(
                label: "앱",
                url: "https://example.com/app",
                relation: .made,
                lastMentionedAt: Date(timeIntervalSince1970: 1_770_000_000)
            )
        ])]
    )
    let model = makeModel(notes: store)
    await model.reload()
    let entry = try #require(model.people.first)

    model.editLink(
        PersonLink(
            label: "메뉴바 달력 앱",
            url: "https://example.com/app",
            relation: .made,
            lastMentionedAt: Date(timeIntervalSince1970: 1_770_000_000)
        ),
        at: 0,
        for: entry
    )

    let link = try #require(model.draft(for: entry).links.first)
    #expect(link.label == "메뉴바 달력 앱")
    #expect(link.relation == .made)
    #expect(link.lastMentionedAt != nil)
}

// MARK: - 고정

/// The one-way door this replaced. Saving a correction used to set the flag
/// `savePeople` reads before overwriting anybody, and nothing in the app ever
/// cleared it — so fixing a name meant never learning another fact about that
/// person. A correction is now just a correction.
@Test @MainActor
func correctingANoteDoesNotPinIt() async throws {
    let store = FakePersonNoteStore([personNote("s-kang", in: studio, name: "강민석", note: "예전 메모")])
    let model = makeModel(notes: store)
    await model.reload()
    let entry = try #require(model.people.first)

    model.editNote("대학 동기, 서로 반말", for: entry)
    await model.save(for: entry)

    #expect(store.saved(inRoom: studio.id, senderID: "s-kang")?.note == "대학 동기, 서로 반말")
    #expect(store.saved(inRoom: studio.id, senderID: "s-kang")?.isPinned == false)
}

/// The checkbox reaches disk without a 저장 press. The sweep reads this flag to
/// decide whether it may rewrite the note, and a pin sitting in an unsaved draft
/// would not stop the refresh that arrives while somebody is still reading the
/// sentence they meant to protect.
@Test @MainActor
func theCheckboxPinsImmediatelyWithoutASavePress() async throws {
    let store = FakePersonNoteStore([personNote("s-kang", in: studio, name: "강민석", note: "예전 메모")])
    let model = makeModel(notes: store)
    await model.reload()
    let entry = try #require(model.people.first)

    await model.setPinned(true, for: entry)

    #expect(store.saved(inRoom: studio.id, senderID: "s-kang")?.isPinned == true)
    #expect(model.people.first?.note.isPinned == true)

    await model.setPinned(false, for: try #require(model.people.first))

    #expect(store.saved(inRoom: studio.id, senderID: "s-kang")?.isPinned == false)
}

/// Pinning must not store half a sentence somebody is mid-way through rewriting.
/// The text is 저장's business; the checkbox is only about the switch.
@Test @MainActor
func pinningDoesNotStoreAnUnsavedDraft() async throws {
    let store = FakePersonNoteStore([personNote("s-kang", in: studio, name: "강민석", note: "예전 메모")])
    let model = makeModel(notes: store)
    await model.reload()
    let entry = try #require(model.people.first)

    model.editNote("아직 쓰는 중인 문장", for: entry)
    await model.setPinned(true, for: entry)

    #expect(store.saved(inRoom: studio.id, senderID: "s-kang")?.note == "예전 메모")
    #expect(store.saved(inRoom: studio.id, senderID: "s-kang")?.isPinned == true)
    #expect(model.hasUnsavedChanges(try #require(model.people.first)))
}
