import Foundation
import Testing
import TalkFlowDomain
@testable import TalkFlowApplication

private let clock = Date(timeIntervalSince1970: 1_700_000_000)

private func conversation(_ count: Int, from index: Int = 1) -> [ChatMessage] {
    (index..<(index + count)).map {
        testMessage(id: "m\($0)", body: "메시지 \($0)", sentAt: clock.addingTimeInterval(Double($0)))
    }
}

private func rememberingPolicy(
    room: ChatRoom = testDirectRoom,
    remembers: Bool = true,
    remembersPeople: Bool = false,
    mode: ResponseMode = .automatic
) -> RoomPolicy {
    RoomPolicy(
        accountFingerprint: testAccount.fingerprint,
        chatRoomID: room.id,
        responseMode: mode,
        remembersConversation: remembers,
        remembersPeople: remembersPeople
    )
}

private func storedSummary(
    _ text: String,
    room: ChatRoom = testDirectRoom,
    updatedAt: Date = clock,
    isPinned: Bool = false,
    through: String?,
    covered: Int = 0
) -> ConversationSummary {
    ConversationSummary(
        accountFingerprint: testAccount.fingerprint,
        chatRoomID: room.id,
        text: text,
        updatedAt: updatedAt,
        isPinned: isPinned,
        coveredThroughMessageID: through,
        coveredMessageCount: covered
    )
}

private func makeSweep(
    rooms: [ChatRoom] = [testDirectRoom],
    messages: [ChatMessage],
    roomID: String = testDirectRoom.id,
    policies: [RoomPolicy],
    summaries: FakeSummaryStore = FakeSummaryStore(),
    settings: FakeSettingsStore = FakeSettingsStore(),
    writer: FakeSummaryWriter = FakeSummaryWriter()
) -> RefreshConversationSummaries {
    RefreshConversationSummaries(
        connection: FakeKakaoConnection(
            rooms: rooms,
            messagesByRoom: [roomID: messages]
        ),
        policyStore: FakePolicyStore(policies),
        settingsStore: settings,
        summaryStore: summaries,
        writer: writer
    )
}

/// The whole point of the layer. A new note is `model(old note + what happened
/// since)`, never `model(everything)` — otherwise the cost of remembering a room
/// grows with the room, and the largest room measured here already holds 1,492
/// messages.
@Test
func aRefreshReadsTheOldNoteAndOnlyTheMessagesAfterIt() async {
    let writer = FakeSummaryWriter()
    let summaries = FakeSummaryStore([
        storedSummary("이번 주 저녁 약속을 잡는 중.", through: "m60", covered: 60)
    ])
    let sweep = makeSweep(
        messages: conversation(100),
        policies: [rememberingPolicy()],
        summaries: summaries,
        writer: writer
    )

    await sweep(now: clock)

    let request = await writer.lastRequest
    #expect(await writer.callCount == 1)
    #expect(request?.previous?.text == "이번 주 저녁 약속을 잡는 중.")
    #expect(request?.newMessages.map(\.id) == (61...100).map { "m\($0)" })
    #expect(request?.newMessages.count == 40)
}

/// The count is cumulative and the anchor moves forward, so the next refresh
/// starts where this one stopped rather than a fixed window back.
@Test
func theStoredNoteRemembersHowFarItHasRead() async {
    let summaries = FakeSummaryStore([
        storedSummary("지난 요약", through: "m60", covered: 60)
    ])
    let sweep = makeSweep(
        messages: conversation(100),
        policies: [rememberingPolicy()],
        summaries: summaries
    )

    await sweep(now: clock)

    let saved = try? await summaries.summary(for: testDirectRoom, accountFingerprint: testAccount.fingerprint)
    #expect(saved?.coveredThroughMessageID == "m100")
    #expect(saved?.coveredMessageCount == 100)
    #expect(saved?.isPinned == false)
}

/// A pinned note is not touched at all — not even to read the room, so it costs
/// nothing as well as changing nothing.
@Test
func aPinnedNoteSurvivesEveryBackgroundRefresh() async {
    let writer = FakeSummaryWriter()
    let summaries = FakeSummaryStore([
        storedSummary(
            "前 직장 동료. 존댓말 유지.",
            updatedAt: clock.addingTimeInterval(-ConversationSummaryRefresh.staleAfter * 5),
            isPinned: true,
            through: "m10",
            covered: 10
        )
    ])
    let sweep = makeSweep(
        messages: conversation(300),
        policies: [rememberingPolicy()],
        summaries: summaries,
        writer: writer
    )

    await sweep(now: clock)

    let saved = try? await summaries.summary(for: testDirectRoom, accountFingerprint: testAccount.fingerprint)
    #expect(await writer.callCount == 0)
    #expect(saved?.text == "前 직장 동료. 존댓말 유지.")
    #expect(saved?.isPinned == true)
}

/// 지금 갱신 stops at 고정 exactly as the sweep does, and says so rather than
/// appearing to work. The button used to override the flag on the grounds that the
/// user had asked — which held only while the flag was set by typing. Once the pin
/// is a switch somebody deliberately threw, honouring it is the point of it.
@Test
func theButtonRefusesAPinnedNoteAndSaysWhy() async {
    let writer = FakeSummaryWriter(answer: "前 직장 동료. 존댓말 유지. 발표 준비 중.")
    let summaries = FakeSummaryStore([
        storedSummary("前 직장 동료. 존댓말 유지.", isPinned: true, through: "m10", covered: 10)
    ])
    let manage = ManageConversationSummary(
        connection: FakeKakaoConnection(messagesByRoom: [testDirectRoom.id: conversation(30)]),
        summaryStore: summaries,
        writer: writer
    )

    await #expect(throws: ConversationSummaryError.pinned) {
        try await manage.refreshNow(for: testDirectRoom)
    }
    #expect(await writer.callCount == 0)
    let saved = try? await summaries.summary(for: testDirectRoom, accountFingerprint: testAccount.fingerprint)
    #expect(saved?.text == "前 직장 동료. 존댓말 유지.")
}

/// And an unpinned note the user typed into *is* refreshed, which is the change:
/// correcting a sentence is a correction, not a decision to freeze the room.
@Test
func theButtonRefreshesANoteSomebodyEditedButDidNotPin() async {
    let writer = FakeSummaryWriter(answer: "前 직장 동료. 존댓말 유지. 발표 준비 중.")
    let summaries = FakeSummaryStore([
        storedSummary("前 직장 동료. 존댓말 유지.", through: "m10", covered: 10)
    ])
    let manage = ManageConversationSummary(
        connection: FakeKakaoConnection(messagesByRoom: [testDirectRoom.id: conversation(30)]),
        summaryStore: summaries,
        writer: writer
    )

    let refreshed = try? await manage.refreshNow(for: testDirectRoom)

    #expect(await writer.lastRequest?.previous?.text == "前 직장 동료. 존댓말 유지.")
    #expect(refreshed?.text == "前 직장 동료. 존댓말 유지. 발표 준비 중.")
    #expect(refreshed?.isPinned == false)
}

/// 고정 is written on its own, and the text it protects is left exactly as it was.
@Test
func pinningLeavesTheSentenceAloneAndUnpinningLetsTheSweepBackIn() async throws {
    let summaries = FakeSummaryStore([
        storedSummary("前 직장 동료. 존댓말 유지.", through: "m10", covered: 10)
    ])
    let manage = ManageConversationSummary(
        connection: FakeKakaoConnection(),
        summaryStore: summaries,
        writer: FakeSummaryWriter()
    )

    let pinned = try await manage.setPinned(true, for: testDirectRoom)
    #expect(pinned.isPinned)
    #expect(pinned.text == "前 직장 동료. 존댓말 유지.")
    #expect(pinned.coveredThroughMessageID == "m10")
    #expect(!ConversationSummaryRefresh.isDue(pinned, newMessageCount: 300, now: clock))

    let released = try await manage.setPinned(false, for: testDirectRoom)
    #expect(!released.isPinned)
    #expect(released.text == "前 직장 동료. 존댓말 유지.")
    #expect(ConversationSummaryRefresh.isDue(released, newMessageCount: 300, now: clock))
}

/// A note can be written by hand for a room that has never had one. "前 직장 동료,
/// 존댓말 유지" is not derivable from any amount of conversation and should not
/// have to wait on a model call to become sayable.
@Test
func aRoomWithNoNoteCanStillBeGivenOneByHand() async {
    let summaries = FakeSummaryStore()
    let manage = ManageConversationSummary(
        connection: FakeKakaoConnection(),
        summaryStore: summaries,
        writer: FakeSummaryWriter()
    )

    let saved = try? await manage.saveEdit("前 직장 동료. 존댓말 유지.", for: testDirectRoom)

    #expect(saved?.text == "前 직장 동료. 존댓말 유지.")
    // Typed, not pinned. The sentence is theirs and the refresh may still fold new
    // conversation into it — 고정 is the checkbox beside the field.
    #expect(saved?.isPinned == false)
}

@Test
func anOverlongEditIsRefusedRatherThanShortened() async throws {
    let summaries = FakeSummaryStore()
    let manage = ManageConversationSummary(
        connection: FakeKakaoConnection(),
        summaryStore: summaries,
        writer: FakeSummaryWriter()
    )

    await #expect(throws: ConversationSummaryError.self) {
        try await manage.saveEdit(
            String(repeating: "가", count: ConversationSummary.characterLimit + 1),
            for: testDirectRoom
        )
    }
    let stored = try await summaries.summary(
        for: testDirectRoom,
        accountFingerprint: testAccount.fingerprint
    )
    #expect(stored == nil)
}

/// 지우기 leaves nothing behind. The row is a written description of people the
/// user knows, and the only honest reading of the button is that it is gone.
@Test
func clearingRemovesTheNoteRatherThanBlankingIt() async throws {
    let summaries = FakeSummaryStore([storedSummary("가족방", through: "m10")])
    let manage = ManageConversationSummary(
        connection: FakeKakaoConnection(),
        summaryStore: summaries,
        writer: FakeSummaryWriter()
    )

    try await manage.clear(for: testDirectRoom)

    let stored = try await summaries.summary(
        for: testDirectRoom,
        accountFingerprint: testAccount.fingerprint
    )
    #expect(stored == nil)
    #expect(await summaries.clearedRoomIDs == [testDirectRoom.id])
}

@Test
func aRoomThatHasNotAccumulatedEnoughIsNotWorthACall() async {
    let writer = FakeSummaryWriter()
    let sweep = makeSweep(
        messages: conversation(ConversationSummaryRefresh.messageThreshold - 1),
        policies: [rememberingPolicy()],
        writer: writer
    )

    await sweep(now: clock)

    #expect(await writer.callCount == 0)
}

/// A room the user switched off gets no note. This app does not write
/// descriptions of people in rooms it was told to stay out of, and the call would
/// be spent on a room that answers nobody.
@Test
func aRoomThatAnswersNobodyIsNeverSummarised() async {
    let writer = FakeSummaryWriter()
    let sweep = makeSweep(
        messages: conversation(200),
        policies: [rememberingPolicy(mode: .detectOnly)],
        writer: writer
    )

    await sweep(now: clock)

    #expect(await writer.callCount == 0)
}

@Test
func aRoomWithTheSettingOffIsNeverSummarised() async {
    let writer = FakeSummaryWriter()
    let sweep = makeSweep(
        messages: conversation(200),
        policies: [rememberingPolicy(remembers: false)],
        writer: writer
    )

    await sweep(now: clock)

    #expect(await writer.callCount == 0)
}

/// The global switch stops spending, not only speaking. A paused app that kept
/// paying for notes would be the emergency stop failing to stop the part the user
/// sees on the bill.
@Test
func theGlobalPauseStopsRefreshesBeforeAnyModelCall() async {
    let writer = FakeSummaryWriter()
    let sweep = makeSweep(
        messages: conversation(200),
        policies: [rememberingPolicy()],
        settings: FakeSettingsStore(enabled: false),
        writer: writer
    )

    await sweep(now: clock)

    #expect(await writer.callCount == 0)
}

/// An empty answer is not a summary of a quiet room; it is a value that would
/// erase a good note.
@Test
func anEmptyAnswerLeavesTheExistingNoteStanding() async {
    let summaries = FakeSummaryStore([storedSummary("이번 주 저녁 약속을 잡는 중.", through: "m10", covered: 10)])
    let sweep = makeSweep(
        messages: conversation(200),
        policies: [rememberingPolicy()],
        summaries: summaries,
        writer: FakeSummaryWriter(answer: "   ")
    )

    await sweep(now: clock)

    let saved = try? await summaries.summary(for: testDirectRoom, accountFingerprint: testAccount.fingerprint)
    #expect(saved?.text == "이번 주 저녁 약속을 잡는 중.")
}

/// Bootstrapping is bounded too. KakaoTalk only syncs a chat once it is opened, so
/// today's history is young — and it will not stay that way. Reading "all of it"
/// would make the first call's size depend on how long the user has had the app:
/// the largest room measured here already holds 1,492 messages from two days.
@Test
func bootstrappingReadsABoundedSliceRatherThanTheWholeHistory() async {
    let writer = FakeSummaryWriter()
    let sweep = makeSweep(
        messages: conversation(1_500),
        policies: [rememberingPolicy()],
        writer: writer
    )

    await sweep(now: clock)

    let request = await writer.lastRequest
    #expect(await writer.callCount == 1)
    #expect((request?.newMessages.count ?? 0) <= ConversationSummaryRefresh.historyLimit)
    #expect(request?.newMessages.last?.id == "m1500")
}

/// The other bound on one call. A room that pasted a few very long messages can
/// reach the character budget well before the message count, and what the budget
/// drops is told to the model rather than hidden.
@Test
func aRefreshFullOfLongMessagesSaysWhatItHadToLeaveOut() async {
    let writer = FakeSummaryWriter()
    let long = (1...60).map {
        testMessage(
            id: "m\($0)",
            body: String(repeating: "가", count: 400),
            sentAt: clock.addingTimeInterval(Double($0))
        )
    }
    let sweep = makeSweep(messages: long, policies: [rememberingPolicy()], writer: writer)

    await sweep(now: clock)

    let request = await writer.lastRequest
    #expect((request?.omittedMessageCount ?? 0) > 0)
    #expect((request?.newMessages.count ?? 0) < 60)
}

// MARK: - 사람 메모가 비워지는 경우

/// A note whose every item has finished should end up gone rather than carrying
/// last week's errand forever. The prompt now asks for an empty answer when there
/// is nothing durable left, so the empty answer has to actually remove the row —
/// otherwise the model has been given a way to say something the store ignores.
@Test
func anEmptyAnswerRemovesTheNoteRatherThanLeavingTheOldOneStanding() async throws {
    let store = PerRoomPersonNoteStore([
        PersonNote(
            chatRoomID: "room-studio",
            senderID: "s-kang",
            displayName: "강민석",
            note: "지난주 작업을 마쳤다고 함.",
            updatedAt: clock
        )
    ])
    let refresher = refresherWritingPeople(into: store)

    await refresher.savePeople(
        [PersonNoteUpdate(senderID: "s-kang", note: "   ")],
        seenIn: [],
        known: [try #require(await store.note(inRoom: "room-studio", senderID: "s-kang"))],
        now: clock
    )

    #expect(try await store.note(inRoom: "room-studio", senderID: "s-kang") == nil)
}

/// What somebody typed about their own friend is not the model's to clear. The
/// hand-edited flag already stops an overwrite, and it has to stop a removal too —
/// a delete is the overwrite there is no way back from.
@Test
func anEmptyAnswerLeavesAHandEditedNoteAlone() async throws {
    let mine = PersonNote(
        chatRoomID: "room-studio",
        senderID: "s-kang",
        displayName: "강민석",
        note: "대학 동기, 서로 반말",
        isPinned: true,
        updatedAt: clock
    )
    let store = PerRoomPersonNoteStore([mine])
    let refresher = refresherWritingPeople(into: store)

    await refresher.savePeople(
        [PersonNoteUpdate(senderID: "s-kang", note: "")],
        seenIn: [],
        known: [mine],
        now: clock
    )

    #expect(try await store.note(inRoom: "room-studio", senderID: "s-kang")?.note == "대학 동기, 서로 반말")
}

/// An answer is written back to the room it was asked about and nowhere else. The
/// same person in another room is another note, and a save that reached it would
/// undo the reason the room is in the key.
@Test
func ananswerOnlyTouchesTheRoomItWasAskedAbout() async throws {
    let inStudio = PersonNote(
        chatRoomID: "room-studio",
        senderID: "s-kang",
        displayName: "강민석",
        note: "스튜디오 메모",
        updatedAt: clock
    )
    let store = PerRoomPersonNoteStore([
        inStudio,
        PersonNote(
            chatRoomID: "room-family",
            senderID: "s-kang",
            displayName: "강민석",
            note: "가족 메모",
            updatedAt: clock
        )
    ])
    let refresher = refresherWritingPeople(into: store)

    await refresher.savePeople(
        [PersonNoteUpdate(senderID: "s-kang", note: "사진 정리 앱을 만든다고 함.")],
        seenIn: [],
        known: [inStudio],
        now: clock
    )

    #expect(try await store.note(inRoom: "room-studio", senderID: "s-kang")?.note == "사진 정리 앱을 만든다고 함.")
    #expect(try await store.note(inRoom: "room-family", senderID: "s-kang")?.note == "가족 메모")
}

private func refresherWritingPeople(into store: PerRoomPersonNoteStore) -> ConversationSummaryRefresher {
    ConversationSummaryRefresher(
        connection: FakeKakaoConnection(),
        summaryStore: FakeSummaryStore(),
        writer: FakeSummaryWriter(),
        personNotes: store,
        policyStore: nil,
        actionLog: nil
    )
}

/// Keyed the way the real store is, so a test cannot pass by merging two rooms.
private actor PerRoomPersonNoteStore: PersonNoteStore {
    private var stored: [String: PersonNote] = [:]

    init(_ notes: [PersonNote]) {
        for note in notes {
            stored[Self.key(note.chatRoomID, note.senderID)] = note
        }
    }

    func note(inRoom chatRoomID: String, senderID: String) async throws -> PersonNote? {
        stored[Self.key(chatRoomID, senderID)]
    }

    func notes(inRoom chatRoomID: String, accountFingerprint: String) async throws -> [PersonNote] {
        stored.values.filter { $0.chatRoomID == chatRoomID }
    }

    func save(_ note: PersonNote) async throws {
        stored[Self.key(note.chatRoomID, note.senderID)] = note
    }

    func delete(inRoom chatRoomID: String, senderID: String) async throws {
        stored[Self.key(chatRoomID, senderID)] = nil
    }

    private static func key(_ chatRoomID: String, _ senderID: String) -> String {
        "\(chatRoomID)\u{1}\(senderID)"
    }
}

// MARK: - 명단은 대화에서 말한 사람으로 좁혀진다

/// The room hands over everybody it has ever answered, and the model is given
/// forty messages. On the largest measured room that was 60 names against 5
/// speakers, so 55 arrived with no evidence and the answer that came back covered
/// 14 of them — the rest dropped with nothing recorded to say so.
@Test
func onlyPeopleWhoSpokeInTheseMessagesAreAskedAbout() async throws {
    let refresher = ConversationSummaryRefresher(
        connection: FakeKakaoConnection(),
        summaryStore: FakeSummaryStore(),
        writer: FakeSummaryWriter(),
        personNotes: PerRoomPersonNoteStore([]),
        policyStore: FakePolicyStore([
            rememberingPolicy(room: testGroupRoom, remembersPeople: true)
        ]),
        actionLog: FakeActionLog(replyCounts: [
            (senderID: "s-spoke", displayName: "말한 사람", count: 9),
            (senderID: "s-quiet", displayName: "조용한 사람", count: 40)
        ])
    )

    let eligible = await refresher.eligiblePeople(
        in: testGroupRoom,
        accountFingerprint: testAccount.fingerprint,
        speaking: [testMessage(id: "m1", roomID: testGroupRoom.id, senderID: "s-spoke", body: "안녕")]
    )

    #expect(eligible.map(\.senderID) == ["s-spoke"])
}

/// Being answered often is not evidence about this conversation, and being in it
/// is not evidence a note would ever be used. Both filters have to hold, or the
/// list grows back to everybody present.
@Test
func speakingIsNotEnoughOnItsOwnAndNeitherIsHavingBeenAnswered() async throws {
    let refresher = ConversationSummaryRefresher(
        connection: FakeKakaoConnection(),
        summaryStore: FakeSummaryStore(),
        writer: FakeSummaryWriter(),
        personNotes: PerRoomPersonNoteStore([]),
        policyStore: FakePolicyStore([
            rememberingPolicy(room: testGroupRoom, remembersPeople: true)
        ]),
        actionLog: FakeActionLog(replyCounts: [
            (senderID: "s-barely", displayName: "두 번 답한 사람", count: PersonNote.replyThreshold - 1)
        ])
    )

    let eligible = await refresher.eligiblePeople(
        in: testGroupRoom,
        accountFingerprint: testAccount.fingerprint,
        speaking: [
            testMessage(id: "m1", roomID: testGroupRoom.id, senderID: "s-barely", body: "안녕"),
            testMessage(id: "m2", roomID: testGroupRoom.id, senderID: "s-unanswered", body: "저도요")
        ]
    )

    #expect(eligible.isEmpty)
}

/// This account is not a person it keeps notes about, so its own messages cannot
/// put it on the list — however many times it has been "answered".
@Test
func theAccountsOwnMessagesDoNotPutItOnTheList() async throws {
    let refresher = ConversationSummaryRefresher(
        connection: FakeKakaoConnection(),
        summaryStore: FakeSummaryStore(),
        writer: FakeSummaryWriter(),
        personNotes: PerRoomPersonNoteStore([]),
        policyStore: FakePolicyStore([
            rememberingPolicy(room: testGroupRoom, remembersPeople: true)
        ]),
        actionLog: FakeActionLog(replyCounts: [
            (senderID: "s-me", displayName: "나", count: 30)
        ])
    )

    let eligible = await refresher.eligiblePeople(
        in: testGroupRoom,
        accountFingerprint: testAccount.fingerprint,
        speaking: [
            testMessage(id: "m1", roomID: testGroupRoom.id, senderID: "s-me", body: "제가 쓴 말", isFromMe: true)
        ]
    )

    #expect(eligible.isEmpty)
}

/// 고정 is the only thing that stops a person note being rewritten, and an
/// unpinned note is rewritten however much of it somebody typed. That second half
/// was unreachable before: the flag protecting a correction was set by making one.
@Test
func theRefreshSkipsAPinnedPersonNoteAndRewritesAnUnpinnedOne() async throws {
    let pinned = PersonNote(
        chatRoomID: "room-studio",
        senderID: "s-pin",
        displayName: "고정한 사람",
        note: "지켜야 하는 문장",
        isPinned: true,
        updatedAt: clock
    )
    let open = PersonNote(
        chatRoomID: "room-studio",
        senderID: "s-open",
        displayName: "안 고정한 사람",
        note: "사람이 고쳐 쓴 문장",
        updatedAt: clock
    )
    let store = PerRoomPersonNoteStore([pinned, open])
    let refresher = refresherWritingPeople(into: store)

    await refresher.savePeople(
        [
            PersonNoteUpdate(senderID: "s-pin", note: "모델이 새로 쓴 문장"),
            PersonNoteUpdate(senderID: "s-open", note: "모델이 새로 쓴 문장")
        ],
        seenIn: [],
        known: [pinned, open],
        now: clock.addingTimeInterval(60)
    )

    #expect(try await store.note(inRoom: "room-studio", senderID: "s-pin")?.note == "지켜야 하는 문장")
    #expect(try await store.note(inRoom: "room-studio", senderID: "s-open")?.note == "모델이 새로 쓴 문장")
    // And the rewrite did not quietly unpin anybody.
    #expect(try await store.note(inRoom: "room-studio", senderID: "s-open")?.isPinned == false)
}

/// An empty answer removes an unpinned note, and cannot remove a pinned one. A
/// delete is the overwrite there is no way back from.
@Test
func anEmptyAnswerCannotRemoveAPinnedNote() async throws {
    let pinned = PersonNote(
        chatRoomID: "room-studio",
        senderID: "s-pin",
        displayName: "고정한 사람",
        note: "지켜야 하는 문장",
        isPinned: true,
        updatedAt: clock
    )
    let store = PerRoomPersonNoteStore([pinned])
    let refresher = refresherWritingPeople(into: store)

    await refresher.savePeople(
        [PersonNoteUpdate(senderID: "s-pin", note: "")],
        seenIn: [],
        known: [pinned],
        now: clock
    )

    #expect(try await store.note(inRoom: "room-studio", senderID: "s-pin")?.note == "지켜야 하는 문장")
}
