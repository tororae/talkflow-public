import Foundation
import Testing
import TalkFlowApplication
import TalkFlowDomain
@testable import TalkFlowFeatures

private let groupRoom = ChatRoom(id: "room-g", displayName: "달빛 스튜디오", kind: .group)

@Test @MainActor
func aRoomShowsTheNameTheGlobalKeywordsAndItsOwnAsOneSet() async throws {
    let model = makeModel(
        account: testAccount.named("달구지톡"),
        globalKeywords: ["달구봇"],
        stored: [policy(keywords: ["달빛"])]
    )
    await model.reload()

    let signs = model.callSigns(for: try #require(model.entries.first))

    #expect(signs.nickname == "달구지톡")
    #expect(signs.globalKeywords == ["달구봇"])
    #expect(signs.roomKeywords == ["달빛"])
    #expect(signs.all == ["달구지톡", "달구봇", "달빛"])
}

/// Nothing is registered per room until the user registers it. The name and the
/// global keywords are what a room answers to out of the box.
@Test @MainActor
func aRoomStartsWithNoKeywordsOfItsOwn() async throws {
    let model = makeModel(account: testAccount.named("달구지톡"), globalKeywords: ["달구봇"])
    await model.reload()
    let entry = try #require(model.entries.first)

    #expect(entry.policy.responseKeywords.isEmpty)
    #expect(model.callSigns(for: entry).roomKeywords.isEmpty)
    #expect(model.callSigns(for: entry).matches("달구지톡 있어?"))
}

/// A keyword waits for 저장 like everything else on the room screen. It used to
/// write itself the moment it was accepted, which left the screen following two
/// rules at once and 취소 unable to take back a word the user had just tried.
@Test @MainActor
func addingARoomKeywordIsHeldUntilSavedAndLeavesTheOtherRoomsAlone() async throws {
    let store = FakeRoomPolicyStore()
    let model = makeModel(policyStore: store)
    await model.reload()
    let entry = try #require(model.entries.first)

    #expect(model.addKeyword("달빛", to: entry))
    #expect(store.saved(groupRoom.id)?.responseKeywords != ["달빛"])
    #expect(model.hasUnsavedChanges(entry))

    await model.saveEdits(for: entry)

    #expect(store.saved(groupRoom.id)?.responseKeywords == ["달빛"])
    #expect(!model.hasUnsavedChanges(try #require(model.entries.first)))
}

@Test @MainActor
func removingARoomKeywordLeavesTheRest() async throws {
    let store = FakeRoomPolicyStore()
    let model = makeModel(policyStore: store, stored: [policy(keywords: ["달빛", "dalbit"])])
    await model.reload()
    let entry = try #require(model.entries.first)

    model.removeKeyword("달빛", from: entry)
    await model.saveEdits(for: entry)

    #expect(store.saved(groupRoom.id)?.responseKeywords == ["dalbit"])
}

/// The whole point of 취소: a value tried and thought better of leaves nothing
/// behind. There was no way back before, because there was no before.
@Test @MainActor
func cancellingPutsTheRoomBackTheWayItWasOnDisk() async throws {
    let store = FakeRoomPolicyStore()
    let model = makeModel(policyStore: store, stored: [policy(keywords: ["dalbit"])])
    await model.reload()
    let entry = try #require(model.entries.first)

    #expect(model.addKeyword("달빛", to: entry))
    #expect(model.hasUnsavedChanges(entry))

    model.revertEdits(for: entry)

    #expect(!model.hasUnsavedChanges(entry))
    #expect(model.editedPolicy(for: entry).responseKeywords == ["dalbit"])
    #expect(store.saved(groupRoom.id)?.responseKeywords == ["dalbit"])
}

/// An edit that lands back on the stored value is not an edit. Leaving 저장 lit
/// with nothing to save teaches the user to ignore it.
@Test @MainActor
func returningAValueToWhereItStartedClearsTheUnsavedMark() async throws {
    let store = FakeRoomPolicyStore()
    let model = makeModel(policyStore: store, stored: [policy(keywords: ["dalbit"])])
    await model.reload()
    let entry = try #require(model.entries.first)

    #expect(model.addKeyword("달빛", to: entry))
    model.removeKeyword("달빛", from: entry)

    #expect(!model.hasUnsavedChanges(entry))
    #expect(model.unsavedRoomIDs.isEmpty)
}

/// A word the room already answers to would sit in the list looking like it does
/// something. The name is called out separately, because "already registered"
/// would send the user looking for a keyword they never typed.
@Test @MainActor
func aWordTheRoomAlreadyAnswersToIsRefusedWithTheReason() async throws {
    let model = makeModel(
        account: testAccount.named("달구지톡"),
        globalKeywords: ["달구봇"],
        stored: [policy(keywords: ["달빛"])]
    )
    await model.reload()
    let entry = try #require(model.entries.first)

    #expect(model.addKeyword("  ", to: entry) == false)
    #expect(model.keywordIssue == "키워드를 입력해 주세요.")
    #expect(model.addKeyword("달구지톡", to: entry) == false)
    #expect(model.keywordIssue == "이미 내 이름으로 반응합니다.")
    #expect(model.addKeyword("달구봇", to: entry) == false)
    #expect(model.keywordIssue == "이미 등록된 키워드입니다.")
    #expect(model.addKeyword("달빛", to: entry) == false)
    #expect(model.keywordIssue == "이미 등록된 키워드입니다.")
}

/// The measurement that tells a broken setting apart from a quiet room, taken
/// where the setting is.
@Test @MainActor
func openingARoomReportsWhetherAnyoneRecentlyCalledIt() async throws {
    let model = makeModel(
        account: testAccount.named("달구지톡"),
        messages: [
            chatMessage(id: "m1", body: "오늘 회의 몇 시죠?"),
            chatMessage(id: "m2", body: "달구지톡 이거 봐줘")
        ]
    )
    await model.reload()

    await model.inspectRecentCalls(for: try #require(model.entries.first))

    #expect(model.recentCalls?.examinedMessages == 2)
    #expect(model.recentCalls?.matchedMessages == 1)
    #expect(model.recentCalls?.latest?.sign == "달구지톡")
}

/// The other silence the timeline deliberately does not record. A room in the
/// middle of a cycle holds every message and logs none of it, and a cycle of
/// random length is indistinguishable from a broken room unless the screen says
/// when it ends.
@Test @MainActor
func openingAnAccumulatingRoomSaysWhenItsCycleRunsOut() async throws {
    let started = Date(timeIntervalSince1970: 1_000_000)
    let model = makeModel(
        stored: [batchingPolicy(JudgementInterval(shortest: 60, longest: 600))],
        lastJudgement: started
    )
    await model.reload()

    await model.inspectRecentCalls(for: try #require(model.entries.first))

    // Halfway up 60~600 is 330 seconds after the cycle began.
    #expect(model.judgementCycle?.startedAt == started)
    #expect(model.judgementCycle?.dueAt == started.addingTimeInterval(330))
}

/// A cycle counted in messages has no hour to name, so the room says the number
/// this cycle drew instead. That is the part a range hides — 5개~15개 is a
/// different number every cycle — and without it the room looks stuck to anybody
/// who assumed the low end.
@Test @MainActor
func openingARoomCountingMessagesSaysHowManyThisCycleWants() async throws {
    let started = Date(timeIntervalSince1970: 1_000_000)
    let model = makeModel(
        stored: [batchingPolicy(JudgementInterval(measure: .messages, shortest: 5, longest: 15))],
        lastJudgement: started
    )
    await model.reload()

    await model.inspectRecentCalls(for: try #require(model.entries.first))

    // Halfway up 5~15 is ten messages into the cycle.
    #expect(model.judgementCycle?.startedAt == started)
    #expect(model.judgementCycle?.ends == .afterMessages(10))
    #expect(model.judgementCycle?.dueAt == nil)
}

/// A room judging every message has no wait to describe, and saying "곧" about a
/// room that answers immediately would be the same kind of invented promise the
/// help cards exist to undo.
@Test @MainActor
func aRoomJudgingEveryMessageHasNoCycleToShow() async throws {
    let model = makeModel(
        stored: [batchingPolicy(.immediate)],
        lastJudgement: Date(timeIntervalSince1970: 1_000_000)
    )
    await model.reload()

    await model.inspectRecentCalls(for: try #require(model.entries.first))

    #expect(model.judgementCycle == nil)
}

/// Editing the interval moves the deadline, and the line saying when this room
/// next speaks would otherwise keep describing the setting that was replaced.
@Test @MainActor
func changingTheIntervalRereadsWhenTheRoomNextJudges() async throws {
    let started = Date(timeIntervalSince1970: 1_000_000)
    let model = makeModel(
        stored: [batchingPolicy(JudgementInterval(fixed: 60))],
        lastJudgement: started
    )
    await model.reload()
    let entry = try #require(model.entries.first)
    model.selectedRoomID = entry.id
    await model.inspectRecentCalls(for: entry)
    #expect(model.judgementCycle?.dueAt == started.addingTimeInterval(60))

    var longer = entry.policy
    longer.judgementInterval = JudgementInterval(fixed: 600)
    await model.update(longer)

    #expect(model.judgementCycle?.dueAt == started.addingTimeInterval(600))
}

// MARK: - 외부(관리자 명령)에서 바뀐 정책

/// A !세팅 write lands in the store; the rooms screen holds a snapshot. The push
/// refreshes just that room — the row and the "응답 켠 방 N개" count — without the
/// full reload that would re-fetch KakaoTalk's room list.
@Test @MainActor
func anExternalPolicyChangeRefreshesJustThatRoomWithoutAFullReload() async throws {
    let store = FakeRoomPolicyStore()
    let model = makeModel(policyStore: store, stored: [policy(keywords: [])])
    await model.reload()
    let entry = try #require(model.entries.first)
    #expect(entry.policy.responseMode == .mentionOnly)
    #expect(model.summary.contains("응답 켠 방 1개"))

    // The admin write, straight to the store, then the push the pipeline makes.
    var turnedOff = entry.policy
    turnedOff.responseMode = .off
    store.preload(turnedOff)
    await model.applyExternalPolicyChange(roomID: entry.id)

    #expect(model.entries.first?.policy.responseMode == .off)
    #expect(model.summary.contains("응답 켠 방 0개"))
    // No unsaved edit was open, so nothing to warn about.
    #expect(model.wasExternallyChanged(entry) == false)
}

/// With an edit open on the room, the list still takes the fresh value, but the
/// editor keeps its draft and is flagged — 저장 there would overwrite what arrived,
/// and 「바뀐 값 불러오기」 drops the draft and clears the flag.
@Test @MainActor
func anExternalChangeUnderAnUnsavedEditIsFlaggedThenAdoptable() async throws {
    let store = FakeRoomPolicyStore()
    let model = makeModel(policyStore: store, stored: [policy(keywords: ["dalbit"])])
    await model.reload()
    let entry = try #require(model.entries.first)

    #expect(model.addKeyword("달빛", to: entry))
    #expect(model.hasUnsavedChanges(entry))

    var turnedOff = entry.policy
    turnedOff.responseMode = .off
    store.preload(turnedOff)
    await model.applyExternalPolicyChange(roomID: entry.id)

    // List took the fresh value; the draft is kept and the room is flagged.
    #expect(model.entries.first?.policy.responseMode == .off)
    #expect(model.wasExternallyChanged(entry))
    #expect(model.editedPolicy(for: entry).responseKeywords == ["dalbit", "달빛"])

    model.adoptExternalChange(for: entry)
    #expect(!model.wasExternallyChanged(entry))
    #expect(!model.hasUnsavedChanges(entry))
}

// MARK: - 목록에서 숨기기

/// The list is derived from the archive and nothing is ever taken out of it, so
/// it only grows — one account measured here carries 234 rooms, most of them
/// left years ago. Hiding is the way out, and it must not be a way to lose a
/// room's settings.
@Test @MainActor
func hidingARoomTakesItOutOfTheListWithoutLosingIt() async throws {
    let store = FakeRoomPolicyStore()
    let model = makeModel(policyStore: store)
    await model.reload()
    let entry = try #require(model.entries.first)

    await model.hide(entry)

    #expect(!model.entries.contains { $0.id == entry.id })
    #expect(model.hiddenRoomCount == 1)
}

/// One toggle back. A room hidden by accident is a room the user must be able to
/// find, and the settings it was hidden with are still on it.
@Test @MainActor
func aHiddenRoomComesBackWithItsSettingsIntact() async throws {
    let store = FakeRoomPolicyStore()
    store.preload(RoomPolicy(
        accountFingerprint: "katok-test",
        chatRoomID: groupRoom.id,
        responseMode: .mentionOnly,
        responseKeywords: ["달빛"]
    ))
    let model = makeModel(policyStore: store)
    await model.reload()
    let entry = try #require(model.entries.first)

    await model.hide(entry)
    model.showsHiddenRooms = true
    let hidden = try #require(model.entries.first { $0.id == entry.id })
    #expect(hidden.isHidden)
    #expect(hidden.policy.responseKeywords == ["달빛"])

    await model.unhide(hidden)
    model.showsHiddenRooms = false

    let back = try #require(model.entries.first { $0.id == entry.id })
    #expect(!back.isHidden)
    #expect(back.policy.responseKeywords == ["달빛"])
}

/// Absence from KakaoTalk's list is a hint, never a verdict — the list exposes
/// only rendered rows, so a room below the fold reads exactly like one that was
/// left. Nothing acts on it; it is counted so a person can decide.
@Test @MainActor
func aRoomMissingFromKakaoTalkIsMarkedRatherThanRemoved() async throws {
    let model = makeModel(policyStore: FakeRoomPolicyStore())
    await model.reload()

    // The fake connection reports no live list at all, which has to read as
    // "nothing is known" rather than as "every room is gone".
    #expect(model.entries.allSatisfy { $0.isListedByKakaoTalk == nil })
    #expect(model.roomsMissingFromKakaoTalk == 0)
}

// MARK: - Fixtures

private func batchingPolicy(_ interval: JudgementInterval) -> RoomPolicy {
    RoomPolicy(
        accountFingerprint: testAccount.fingerprint,
        chatRoomID: groupRoom.id,
        responseMode: .automatic,
        judgementInterval: interval
    )
}

/// A refused save says so on the screen, in the store's own words, and keeps the
/// edit.
///
/// `RoomPolicyRepository` refuses to overwrite a room whose stored row it cannot
/// decode — a real case, and the only thing standing between a corrupt row and a
/// user's settings being replaced by defaults. That refusal is worth nothing if the
/// screen swallows it: the person would see 저장했습니다 over a room that was not
/// saved. The message is the store's, not this model's, because only the store
/// knows why.
@Test @MainActor
func aRefusedSaveShowsTheStoresReasonAndKeepsTheUnsavedEdit() async throws {
    struct Refusal: LocalizedError {
        var errorDescription: String? { "이 방에 저장된 설정을 읽을 수 없어 아무것도 덮어쓰지 않았습니다." }
    }
    let store = FakeRoomPolicyStore()
    let model = makeModel(policyStore: store, stored: [policy(keywords: ["달빛"])])
    await model.reload()
    let entry = try #require(model.entries.first)
    #expect(model.addKeyword("dalbit-1", to: entry))
    store.refuseSaves(with: Refusal())

    await model.saveEdits(for: entry)

    #expect(model.saveStatus == .failed(Refusal().localizedDescription))
    #expect(store.saved(groupRoom.id)?.responseKeywords == ["달빛"], "거절된 저장이 값을 바꿨습니다")
    #expect(model.hasUnsavedChanges(entry), "거절된 뒤 편집이 사라졌습니다")
    // The whole list goes to `.failed` with the same reason, which is how any save
    // failure has always been drawn here — `ChatRoomsManagementView` puts it in a
    // `ContentUnavailableView`. Pinned so the message is known to reach a person
    // by two routes and to be lost by neither.
    #expect(model.state == .failed(Refusal().localizedDescription))
}

private func policy(keywords: [String]) -> RoomPolicy {
    RoomPolicy(
        accountFingerprint: testAccount.fingerprint,
        chatRoomID: groupRoom.id,
        responseMode: .mentionOnly,
        responseKeywords: keywords
    )
}

private func chatMessage(id: String, body: String) -> ChatMessage {
    ChatMessage(
        id: id,
        chatRoomID: groupRoom.id,
        sender: ChatMember(id: "s1", displayName: "지수"),
        body: body,
        sentAt: Date(timeIntervalSince1970: 1_000_000),
        kind: .text,
        isFromMe: false
    )
}

@MainActor
private func makeModel(
    account: AccountProfile = testAccount,
    globalKeywords: [String] = [],
    policyStore: FakeRoomPolicyStore = FakeRoomPolicyStore(),
    stored: [RoomPolicy] = [],
    messages: [ChatMessage] = [],
    lastJudgement: Date? = nil,
    roll: JudgementRoll = JudgementRoll { _ in 0.5 }
) -> ChatRoomListModel {
    let connection = FakeKakaoConnection(
        statusValue: .connected(account: account),
        rooms: [groupRoom],
        messagesByRoom: [groupRoom.id: messages]
    )
    let settings = FakeSettingsStore(style: ResponseStyle(responseKeywords: globalKeywords))
    for policy in stored {
        policyStore.preload(policy)
    }

    return ChatRoomListModel(
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
        inspectCycle: InspectJudgementCycle(
            actionLog: FakeJudgementLog(lastJudgement: lastJudgement),
            roll: roll
        )
    )
}

/// The keyword editors save in a task of their own, so a test has to give that
/// task a turn before it reads the store back. Yielding on the main actor is
/// what hands the turn over: that is where the model queued the work.
@MainActor
private func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0 ..< 100 {
        if condition() { return true }
        await Task.yield()
    }
    return false
}

/// The room's own 답변 조건 is written the moment it is accepted, like every other
/// switch on this screen — and refused rather than shortened when it is too long,
/// so the field keeps what was typed.
@Test @MainActor
func aRoomsAnsweringConditionIsSavedWhenAcceptedAndRefusedWhenTooLong() async throws {
    let store = FakeRoomPolicyStore()
    let model = makeModel(policyStore: store, stored: [batchingPolicy(.immediate)])
    await model.loadIfNeeded()
    guard let entry = model.entries.first else {
        Issue.record("방이 하나는 있어야 합니다")
        return
    }

    model.setAnsweringCondition("일정 얘기 위주로", for: entry)
    await model.saveEdits(for: entry)

    #expect(model.conditionIssue == nil)
    #expect(store.saved(groupRoom.id)?.answeringConditionOverride?.text == "일정 얘기 위주로")

    let stored = try #require(model.entries.first)
    model.setAnsweringCondition(String(repeating: "가", count: AnsweringCondition.characterLimit + 1), for: stored)
    await model.saveEdits(for: stored)

    #expect(model.conditionIssue != nil)
    #expect(store.saved(groupRoom.id)?.answeringConditionOverride?.text == "일정 얘기 위주로")
}

/// Clearing the override puts the room back on the one in 설정 rather than on an
/// empty condition, which is the other value entirely.
@Test @MainActor
func clearingARoomsConditionPutsItBackOnTheGlobalOne() async {
    var policy = batchingPolicy(.immediate)
    policy.answeringConditionOverride = AnsweringCondition("이 방은 급한 것만")
    let store = FakeRoomPolicyStore()
    let model = makeModel(policyStore: store, stored: [policy])
    await model.loadIfNeeded()
    guard let entry = model.entries.first else {
        Issue.record("방이 하나는 있어야 합니다")
        return
    }

    model.setAnsweringCondition(nil, for: entry)
    await model.saveEdits(for: entry)

    #expect(store.saved(groupRoom.id)?.answeringConditionOverride == nil)
    #expect(store.saved(groupRoom.id)?.usesOwnAnsweringCondition == false)
}

// MARK: - 대화창 열림 여부

/// The one state on this screen a person can fix in a second: a room set to
/// answer on its own whose window is closed. Automatic delivery will not open a
/// closed room — opening one takes the screen and has typed the room's name into
/// a conversation when it went wrong — so its replies wait.
@Test
func aRoomThatAnswersOnItsOwnWithNoWindowIsCalledOut() {
    let entry = ChatRoomPolicy(
        room: groupRoom,
        policy: RoomPolicy(
            accountFingerprint: "katok-test",
            chatRoomID: groupRoom.id,
            responseMode: .automatic,
            deliveryMode: .always
        ),
        hasOpenWindow: false
    )

    #expect(entry.isBlockedByClosedWindow)
}

/// A closed window on a room that only drafts is not a problem, and colouring it
/// would send somebody opening windows for nothing.
@Test
func aClosedWindowOnADraftOnlyRoomIsNotAProblem() {
    let entry = ChatRoomPolicy(
        room: groupRoom,
        policy: RoomPolicy(
            accountFingerprint: "katok-test",
            chatRoomID: groupRoom.id,
            responseMode: .automatic,
            deliveryMode: .draftOnly
        ),
        hasOpenWindow: false
    )

    #expect(!entry.isBlockedByClosedWindow)
}

/// Unknown is not closed. Only the active Space is visible, so a window on
/// another desktop reads as absent — and an unknown drawn as 닫힘 would be a
/// warning about nothing.
@Test
func anUnknownWindowStateIsNotTreatedAsClosed() {
    let entry = ChatRoomPolicy(
        room: groupRoom,
        policy: RoomPolicy(
            accountFingerprint: "katok-test",
            chatRoomID: groupRoom.id,
            responseMode: .automatic,
            deliveryMode: .always
        )
    )

    #expect(!entry.isBlockedByClosedWindow)
}
