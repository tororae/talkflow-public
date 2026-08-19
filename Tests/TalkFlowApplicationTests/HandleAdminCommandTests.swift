import Foundation
import Testing
import TalkFlowDomain
@testable import TalkFlowApplication

/// A store of designated console rooms a test can pre-load. There is no shared
/// admin fake in `PipelineFakes`, so this one lives with the tests that need it.
private actor FakeAdminRoomStore: AdminRoomStore {
    private var ids: Set<String>

    init(_ ids: Set<String> = []) { self.ids = ids }

    func adminRoomIDs(accountFingerprint: String) async throws -> Set<String> { ids }

    func setAdminRoom(_ isAdmin: Bool, chatRoomID: String, accountFingerprint: String) async throws {
        if isAdmin { ids.insert(chatRoomID) } else { ids.remove(chatRoomID) }
    }
}

/// Collected 사람 기억 a test can pre-load per room, so `!유저` reads a real note
/// list rather than deriving one from who spoke.
private actor FakePersonNoteStore: PersonNoteStore {
    private var notesByRoom: [String: [PersonNote]]

    init(_ notesByRoom: [String: [PersonNote]] = [:]) { self.notesByRoom = notesByRoom }

    func note(inRoom chatRoomID: String, senderID: String) async throws -> PersonNote? {
        notesByRoom[chatRoomID]?.first { $0.senderID == senderID }
    }

    func notes(inRoom chatRoomID: String, accountFingerprint: String) async throws -> [PersonNote] {
        notesByRoom[chatRoomID] ?? []
    }

    func save(_ note: PersonNote) async throws {}
    func delete(inRoom chatRoomID: String, senderID: String) async throws {}
}

/// Records the rooms a `!세팅` write announced, so a test can check the UI was told
/// which room to refresh — and told only on a write that landed.
private actor RoomChangeSpy {
    private(set) var roomIDs: [String] = []
    func record(_ id: String) { roomIDs.append(id) }
}

private func personNote(_ senderID: String, _ name: String, _ note: String, in room: ChatRoom = testGroupRoom) -> PersonNote {
    PersonNote(chatRoomID: room.id, senderID: senderID, displayName: name, note: note, updatedAt: Date(timeIntervalSince1970: 0))
}

/// Sorted, the two shared rooms are 가족(1) then 프로젝트 팀(2). The group room is
/// the console in these tests, so a `!방` typed into it lists both by number.
private func makeHandler(
    adminRooms: Set<String>,
    rooms: [ChatRoom] = [testDirectRoom, testGroupRoom],
    messagesByRoom: [String: [ChatMessage]],
    policies: [RoomPolicy] = [],
    personNotes: (any PersonNoteStore)? = nil,
    actionLog: FakeActionLog = FakeActionLog()
) -> (handler: HandleAdminCommand, sender: FakeMessageSender, log: FakeActionLog) {
    let sender = FakeMessageSender()
    let handler = HandleAdminCommand(
        connection: FakeKakaoConnection(rooms: rooms, messagesByRoom: messagesByRoom),
        sender: sender,
        policyStore: FakePolicyStore(policies),
        adminRoomStore: FakeAdminRoomStore(adminRooms),
        personNotes: personNotes,
        actionLog: actionLog
    )
    return (handler, sender, actionLog)
}

private func line(_ body: String, id: String = "m1", in room: ChatRoom = testGroupRoom) -> [String: [ChatMessage]] {
    [room.id: [testMessage(id: id, roomID: room.id, body: body)]]
}

@Test
func aCommandInANonAdminRoomIsNotConsumedAndNothingIsSent() async {
    let (handler, sender, log) = makeHandler(adminRooms: [], messagesByRoom: line("!방"))

    let consumed = await handler.handle(roomID: testGroupRoom.id, account: testAccount)

    #expect(consumed == false)
    #expect(await sender.sent.isEmpty)
    // Nothing recorded either, so the room still falls through to normal drafting.
    #expect(await log.recorded.isEmpty)
}

@Test
func slashRoomsInAnAdminRoomSendsANumberedListingBackIntoThatRoom() async {
    let (handler, sender, log) = makeHandler(adminRooms: [testGroupRoom.id], messagesByRoom: line("!방"))

    let consumed = await handler.handle(roomID: testGroupRoom.id, account: testAccount)

    #expect(consumed == true)
    let sent = await sender.sent
    #expect(sent.count == 1)
    #expect(sent.first?.chatRoomID == testGroupRoom.id)
    #expect(sent.first?.text.contains("방 2개") == true)
    // Every room printed with its name beside its global number.
    #expect(sent.first?.text.contains("1. 가족") == true)
    #expect(sent.first?.text.contains("2. 프로젝트 팀") == true)

    // Recorded once, as its own kind, keyed on the message that triggered it.
    let recorded = await log.recorded
    #expect(recorded.count == 1)
    #expect(recorded.first?.kind == .commanded)
    #expect(recorded.first?.triggerMessageID == "m1")
    #expect(recorded.first?.triggerSenderID == nil)
}

@Test
func aFilterKeepsEachRoomsGlobalNumber() async {
    let rooms = [testDirectRoom, testGroupRoom]
    let (handler, sender, _) = makeHandler(
        adminRooms: [testGroupRoom.id],
        rooms: rooms,
        messagesByRoom: line("!방 프로젝트")
    )

    _ = await handler.handle(roomID: testGroupRoom.id, account: testAccount)

    let text = await sender.sent.first?.text
    // 프로젝트 팀 is the 2nd room globally; a search must not renumber it to 1.
    #expect(text?.contains("2. 프로젝트 팀") == true)
    #expect(text?.contains("1. 가족") == false)
    #expect(text?.contains("전체 2개") == true)
}

@Test
func anUnknownSlashCommandGetsTheUnknownReply() async {
    let (handler, sender, log) = makeHandler(adminRooms: [testGroupRoom.id], messagesByRoom: line("!없는명령"))

    let consumed = await handler.handle(roomID: testGroupRoom.id, account: testAccount)

    #expect(consumed == true)
    let sent = await sender.sent
    #expect(sent.count == 1)
    #expect(sent.first?.text == "모르는 명령입니다. !? 로 목록")
    // Recorded so it is not re-run on the next sync.
    #expect(await log.recorded.count == 1)
}

@Test
func aPlainLineInAnAdminRoomFallsThroughToNormalDrafting() async {
    let (handler, sender, log) = makeHandler(adminRooms: [testGroupRoom.id], messagesByRoom: line("안녕하세요"))

    let consumed = await handler.handle(roomID: testGroupRoom.id, account: testAccount)

    // Not a command, so nothing is consumed and nothing is recorded — the drafting
    // pipeline is still free to judge this message.
    #expect(consumed == false)
    #expect(await sender.sent.isEmpty)
    #expect(await log.recorded.isEmpty)
}

@Test
func theSameCommandIsAnsweredOnceEvenWhenTheSyncRepeats() async {
    let (handler, sender, _) = makeHandler(adminRooms: [testGroupRoom.id], messagesByRoom: line("!방"))

    let first = await handler.handle(roomID: testGroupRoom.id, account: testAccount)
    let second = await handler.handle(roomID: testGroupRoom.id, account: testAccount)

    // Both consume the command — the second because it is already handled — but it
    // is sent only once.
    #expect(first == true)
    #expect(second == true)
    #expect(await sender.sent.count == 1)
}

@Test
func helpListsEveryCommand() async {
    let (handler, sender, _) = makeHandler(adminRooms: [testGroupRoom.id], messagesByRoom: line("!?"))

    _ = await handler.handle(roomID: testGroupRoom.id, account: testAccount)

    let text = await sender.sent.first?.text
    #expect(text?.contains("관리자 명령") == true)
    #expect(text?.contains("!유저 <N> <M>") == true)
}

@Test
func theAccountResolvingEntryPointReadsTheConnectedAccount() async {
    // FakeKakaoConnection is connected as testAccount by default, so the entry
    // point the pipeline uses resolves the account and proceeds.
    let (handler, sender, _) = makeHandler(adminRooms: [testGroupRoom.id], messagesByRoom: line("!방"))

    let consumed = await handler.handle(roomID: testGroupRoom.id)

    #expect(consumed == true)
    #expect(await sender.sent.count == 1)
}

@Test
func anOutOfRangeRoomNumberSaysSo() async {
    let (handler, sender, _) = makeHandler(adminRooms: [testGroupRoom.id], messagesByRoom: line("!방 9"))

    _ = await handler.handle(roomID: testGroupRoom.id, account: testAccount)

    #expect(await sender.sent.first?.text == "그런 번호의 방이 없어요. !방 으로 확인")
}

@Test
func usersListsThePeopleTheRoomHasCollectedInfoOnSortedByName() async {
    // testGroupRoom is the console; a bare !유저 lists its own collected 사람 기억,
    // not who spoke. Sorted by name, 민준 is 1 and 지수 is 2, and each note's first
    // line rides along so they are told apart.
    let notes = FakePersonNoteStore([testGroupRoom.id: [
        personNote("s-ji", "지수", "회의 좋아함"),
        personNote("s-min", "민준", "농담 많음"),
    ]])
    let (handler, sender, _) = makeHandler(
        adminRooms: [testGroupRoom.id],
        messagesByRoom: line("!유저"),
        personNotes: notes
    )

    _ = await handler.handle(roomID: testGroupRoom.id, account: testAccount)

    let text = await sender.sent.first?.text
    #expect(text?.contains("수집한 사람 2명") == true)
    #expect(text?.contains("1. 민준") == true)
    #expect(text?.contains("2. 지수") == true)
    #expect(text?.contains("농담 많음") == true)
}

@Test
func usersSaysNothingIsCollectedWhenTheRoomHasNoNotes() async {
    // An admin room with no collected notes reports the absence rather than
    // inventing a roster from recent speakers.
    let (handler, sender, _) = makeHandler(
        adminRooms: [testGroupRoom.id],
        messagesByRoom: line("!유저"),
        personNotes: FakePersonNoteStore()
    )

    _ = await handler.handle(roomID: testGroupRoom.id, account: testAccount)

    #expect(await sender.sent.first?.text.contains("수집한 사람 0명") == true)
}

@Test
func aMemberNumberShowsThatPersonsFullNote() async {
    let notes = FakePersonNoteStore([testGroupRoom.id: [
        personNote("s-ji", "지수", "회의 좋아함"),
        personNote("s-min", "민준", "농담 많음"),
    ]])
    // 프로젝트 팀 is room 2 globally; sorted by name its person 1 is 민준.
    let (handler, sender, _) = makeHandler(
        adminRooms: [testGroupRoom.id],
        messagesByRoom: line("!유저 2 1"),
        personNotes: notes
    )

    _ = await handler.handle(roomID: testGroupRoom.id, account: testAccount)

    let text = await sender.sent.first?.text
    #expect(text?.contains("민준") == true)
    #expect(text?.contains("메모: 농담 많음") == true)
}

/// A handler holding a store the test can read back, so a write can be checked at
/// the store and not only in the echo. testGroupRoom is 프로젝트 팀, room 2, and the
/// console — so `!세팅 2` writes the room the command was typed in.
private func makeSettingHandler(
    body: String,
    seededPolicy: RoomPolicy
) -> (handler: HandleAdminCommand, sender: FakeMessageSender, store: FakePolicyStore) {
    let sender = FakeMessageSender()
    let store = FakePolicyStore([seededPolicy])
    let handler = HandleAdminCommand(
        connection: FakeKakaoConnection(rooms: [testDirectRoom, testGroupRoom], messagesByRoom: line(body)),
        sender: sender,
        policyStore: store,
        adminRoomStore: FakeAdminRoomStore([testGroupRoom.id]),
        personNotes: nil,
        actionLog: FakeActionLog()
    )
    return (handler, sender, store)
}

@Test
func settingWritesTheFieldAndEchoesTheChange() async {
    let (handler, sender, store) = makeSettingHandler(
        body: "!세팅 2 응답 자동",
        seededPolicy: RoomPolicy(accountFingerprint: testAccount.fingerprint, chatRoomID: testGroupRoom.id, responseMode: .mentionOnly)
    )

    let consumed = await handler.handle(roomID: testGroupRoom.id, account: testAccount)

    #expect(consumed == true)
    // The change landed in the store, not just in the reply.
    let saved = try? await store.policy(for: testGroupRoom, accountFingerprint: testAccount.fingerprint)
    #expect(saved?.responseMode == .automatic)
    #expect(await sender.sent.first?.text.contains("응답: 멘션에만 응답 → 자동응답") == true)
}

@Test
func settingRejectsABadValueWithoutWriting() async {
    let (handler, sender, store) = makeSettingHandler(
        body: "!세팅 2 응답 헐",
        seededPolicy: RoomPolicy(accountFingerprint: testAccount.fingerprint, chatRoomID: testGroupRoom.id, responseMode: .mentionOnly)
    )

    _ = await handler.handle(roomID: testGroupRoom.id, account: testAccount)

    // Unchanged, and answered with the field's allowed list.
    let saved = try? await store.policy(for: testGroupRoom, accountFingerprint: testAccount.fingerprint)
    #expect(saved?.responseMode == .mentionOnly)
    #expect(await sender.sent.first?.text.contains("중 하나로") == true)
}

@Test
func aTogglesetLandsInTheStore() async {
    let (handler, _, store) = makeSettingHandler(
        body: "!세팅 2 사람기억 켬",
        seededPolicy: RoomPolicy(accountFingerprint: testAccount.fingerprint, chatRoomID: testGroupRoom.id, responseMode: .mentionOnly, remembersPeople: false)
    )

    _ = await handler.handle(roomID: testGroupRoom.id, account: testAccount)

    let saved = try? await store.policy(for: testGroupRoom, accountFingerprint: testAccount.fingerprint)
    #expect(saved?.remembersPeople == true)
}

@Test
func aBareSettingPrintsUsageAndNoReplyLeadsWithThePrefix() async {
    let (handler, sender, _) = makeHandler(adminRooms: [testGroupRoom.id], messagesByRoom: line("!세팅"))

    _ = await handler.handle(roomID: testGroupRoom.id, account: testAccount)

    // The usage reply leads with the 「값 바꾸기」 label, not the !세팅 form, so the
    // reply itself never reads back as a command.
    let usage = await sender.sent.first?.text
    #expect(usage?.contains("값 바꾸기") == true)
    #expect(usage?.hasPrefix("!") == false)
}

@Test
func settingWithJustARoomListsTheFieldsAndTheirCurrentValues() async {
    // !세팅 2 → room 2's settable fields, each with its value now and its options.
    let (handler, sender, _) = makeHandler(
        adminRooms: [testGroupRoom.id],
        messagesByRoom: line("!세팅 2"),
        policies: [RoomPolicy(accountFingerprint: testAccount.fingerprint, chatRoomID: testGroupRoom.id, responseMode: .mentionOnly)]
    )

    _ = await handler.handle(roomID: testGroupRoom.id, account: testAccount)

    let text = await sender.sent.first?.text
    #expect(text?.contains("바꿀 항목") == true)
    #expect(text?.contains("응답: 멘션에만 응답 (끔·감지·멘션·자동)") == true)
    #expect(text?.contains("집중시간:") == true)
    #expect(text?.contains("예: !세팅 2 응답 멘션") == true)
    #expect(text?.hasPrefix("!") == false)
}

@Test
func settingWithARoomAndFieldShowsThatFieldsOptionsAndCurrentValue() async {
    // !세팅 2 응답 → 응답's value now + options + how to set it. The gap the user hit.
    let (handler, sender, _) = makeHandler(
        adminRooms: [testGroupRoom.id],
        messagesByRoom: line("!세팅 2 응답"),
        policies: [RoomPolicy(accountFingerprint: testAccount.fingerprint, chatRoomID: testGroupRoom.id, responseMode: .automatic)]
    )

    _ = await handler.handle(roomID: testGroupRoom.id, account: testAccount)

    let text = await sender.sent.first?.text
    #expect(text?.contains("지금: 자동응답") == true)
    #expect(text?.contains("값: 끔·감지·멘션·자동") == true)
    #expect(text?.contains("!세팅 2 응답 <값>") == true)
    #expect(text?.hasPrefix("!") == false)
}

@Test
func settingAnUnknownFieldSaysSoRatherThanInventingOne() async {
    let (handler, sender, _) = makeHandler(
        adminRooms: [testGroupRoom.id],
        messagesByRoom: line("!세팅 2 없는항목"),
        policies: [RoomPolicy(accountFingerprint: testAccount.fingerprint, chatRoomID: testGroupRoom.id, responseMode: .mentionOnly)]
    )

    _ = await handler.handle(roomID: testGroupRoom.id, account: testAccount)

    #expect(await sender.sent.first?.text.contains("그런 항목이 없어요") == true)
}

@Test
func theConsolesOwnMessageIsIgnoredSoItCannotEchoItself() async {
    // Every console reply is isFromMe. The 사용법 line used to begin with the prefix
    // and was answered forever; besides fixing that text, the handler now ignores
    // the account's own messages, so no reply can feed itself. A command typed by
    // the account itself is not consumed and nothing is sent.
    let (handler, sender, log) = makeHandler(
        adminRooms: [testGroupRoom.id],
        messagesByRoom: [testGroupRoom.id: [testMessage(id: "m1", roomID: testGroupRoom.id, body: "!방", isFromMe: true)]]
    )

    let consumed = await handler.handle(roomID: testGroupRoom.id, account: testAccount)

    #expect(consumed == false)
    #expect(await sender.sent.isEmpty)
    #expect(await log.recorded.isEmpty)
}

@Test
func settingAnnouncesTheWrittenRoomSoTheUICanRefreshIt() async {
    let spy = RoomChangeSpy()
    let handler = HandleAdminCommand(
        connection: FakeKakaoConnection(rooms: [testDirectRoom, testGroupRoom], messagesByRoom: line("!세팅 2 응답 자동")),
        sender: FakeMessageSender(),
        policyStore: FakePolicyStore([RoomPolicy(accountFingerprint: testAccount.fingerprint, chatRoomID: testGroupRoom.id, responseMode: .mentionOnly)]),
        adminRoomStore: FakeAdminRoomStore([testGroupRoom.id]),
        personNotes: nil,
        actionLog: FakeActionLog(),
        onRoomPolicyChanged: { await spy.record($0) }
    )

    _ = await handler.handle(roomID: testGroupRoom.id, account: testAccount)

    // Room 2 is testGroupRoom, and it — not the console — is the one to refresh.
    #expect(await spy.roomIDs == [testGroupRoom.id])
}

@Test
func aBadSettingValueAnnouncesNothing() async {
    let spy = RoomChangeSpy()
    let handler = HandleAdminCommand(
        connection: FakeKakaoConnection(rooms: [testDirectRoom, testGroupRoom], messagesByRoom: line("!세팅 2 응답 헐")),
        sender: FakeMessageSender(),
        policyStore: FakePolicyStore([RoomPolicy(accountFingerprint: testAccount.fingerprint, chatRoomID: testGroupRoom.id, responseMode: .mentionOnly)]),
        adminRoomStore: FakeAdminRoomStore([testGroupRoom.id]),
        personNotes: nil,
        actionLog: FakeActionLog(),
        onRoomPolicyChanged: { await spy.record($0) }
    )

    _ = await handler.handle(roomID: testGroupRoom.id, account: testAccount)

    // The value was refused and nothing was written, so nothing to refresh.
    #expect(await spy.roomIDs.isEmpty)
}

// MARK: - !켬 · !끔 · !활동

@Test
func togglingARoomOffSetsResponseModeAndRefreshesTheUI() async {
    let spy = RoomChangeSpy()
    let store = FakePolicyStore([RoomPolicy(accountFingerprint: testAccount.fingerprint, chatRoomID: testGroupRoom.id, responseMode: .automatic)])
    let sender = FakeMessageSender()
    let handler = HandleAdminCommand(
        connection: FakeKakaoConnection(rooms: [testDirectRoom, testGroupRoom], messagesByRoom: line("!끔 2")),
        sender: sender,
        policyStore: store,
        adminRoomStore: FakeAdminRoomStore([testGroupRoom.id]),
        personNotes: nil,
        actionLog: FakeActionLog(),
        onRoomPolicyChanged: { await spy.record($0) }
    )

    _ = await handler.handle(roomID: testGroupRoom.id, account: testAccount)

    let saved = try? await store.policy(for: testGroupRoom, accountFingerprint: testAccount.fingerprint)
    #expect(saved?.responseMode == .off)
    #expect(await spy.roomIDs == [testGroupRoom.id])   // live refresh fired
    #expect(await sender.sent.first?.text.contains("응답: 자동응답 → 끔") == true)
}

@Test
func togglingAGroupRoomOnUsesMentionRatherThanFullAuto() async {
    // A group turned on answers mentions, not everything — the app's own enable rule.
    let (handler, _, store) = makeSettingHandler(
        body: "!켬 2",
        seededPolicy: RoomPolicy(accountFingerprint: testAccount.fingerprint, chatRoomID: testGroupRoom.id, responseMode: .off)
    )

    _ = await handler.handle(roomID: testGroupRoom.id, account: testAccount)

    let saved = try? await store.policy(for: testGroupRoom, accountFingerprint: testAccount.fingerprint)
    #expect(saved?.responseMode == .mentionOnly)
}

@Test
func activityListsRecentBotWorkAndLeavesOutAdminCommands() async {
    let actions = [
        AgentAction(accountFingerprint: testAccount.fingerprint, chatRoomID: testGroupRoom.id, chatRoomName: "프로젝트 팀", kind: .sent, replyText: "곧 갈게요", detail: ""),
        AgentAction(accountFingerprint: testAccount.fingerprint, chatRoomID: testGroupRoom.id, chatRoomName: "프로젝트 팀", kind: .commanded, replyText: "관리자 명령에 답했습니다.", detail: ""),
    ]
    let (handler, sender, _) = makeHandler(
        adminRooms: [testGroupRoom.id],
        messagesByRoom: line("!활동"),
        actionLog: FakeActionLog(existing: actions)
    )

    _ = await handler.handle(roomID: testGroupRoom.id, account: testAccount)

    let text = await sender.sent.first?.text
    #expect(text?.contains("최근 활동 · 1~1") == true)    // 관리자 명령 빠져 1건
    #expect(text?.contains("1. 프로젝트 팀 · 전송 · 곧 갈게요") == true)
    #expect(text?.contains("관리자 명령") == false)
}

@Test
func activityDrillsIntoOneItemInFull() async {
    let actions = [
        AgentAction(accountFingerprint: testAccount.fingerprint, chatRoomID: testGroupRoom.id, chatRoomName: "프로젝트 팀", kind: .sent, triggerText: "어디야?", replyText: "곧 도착해요", detail: "")
    ]
    let (handler, sender, _) = makeHandler(
        adminRooms: [testGroupRoom.id],
        messagesByRoom: line("!활동 2 1"),   // 방 2의 1번째 활동
        actionLog: FakeActionLog(existing: actions)
    )

    _ = await handler.handle(roomID: testGroupRoom.id, account: testAccount)

    let text = await sender.sent.first?.text
    #expect(text?.contains("1번째 활동") == true)
    #expect(text?.contains("한 말: 곧 도착해요") == true)
    #expect(text?.contains("답한 말: 어디야?") == true)
}

@Test
func activityPagesTenAtATime() async {
    let actions = (1...12).map { i in
        AgentAction(id: Int64(i), accountFingerprint: testAccount.fingerprint, chatRoomID: testGroupRoom.id, chatRoomName: "프로젝트 팀", kind: .sent, replyText: "메시지 \(i)", detail: "")
    }

    let (h1, s1, _) = makeHandler(adminRooms: [testGroupRoom.id], messagesByRoom: line("!활동 2"), actionLog: FakeActionLog(existing: actions))
    _ = await h1.handle(roomID: testGroupRoom.id, account: testAccount)
    let page1 = await s1.sent.first?.text
    #expect(page1?.contains("1~10") == true)
    #expect(page1?.contains("다음: !활동 2 2쪽") == true)

    let (h2, s2, _) = makeHandler(adminRooms: [testGroupRoom.id], messagesByRoom: line("!활동 2 2쪽"), actionLog: FakeActionLog(existing: actions))
    _ = await h2.handle(roomID: testGroupRoom.id, account: testAccount)
    let page2 = await s2.sent.first?.text
    #expect(page2?.contains("11~12") == true)
    #expect(page2?.contains("11. 전송 · 메시지 11") == true)
}

@Test
func applyingTheFullPresetWritesAllOfItAndRefreshesTheUI() async {
    let spy = RoomChangeSpy()
    let store = FakePolicyStore([RoomPolicy(accountFingerprint: testAccount.fingerprint, chatRoomID: testGroupRoom.id, responseMode: .off)])
    let sender = FakeMessageSender()
    let handler = HandleAdminCommand(
        connection: FakeKakaoConnection(rooms: [testDirectRoom, testGroupRoom], messagesByRoom: line("!프리셋 2 풀")),
        sender: sender,
        policyStore: store,
        adminRoomStore: FakeAdminRoomStore([testGroupRoom.id]),
        personNotes: nil,
        actionLog: FakeActionLog(),
        onRoomPolicyChanged: { await spy.record($0) }
    )

    _ = await handler.handle(roomID: testGroupRoom.id, account: testAccount)

    let saved = try? await store.policy(for: testGroupRoom, accountFingerprint: testAccount.fingerprint)
    #expect(saved?.responseMode == .automatic)
    #expect(saved?.deliveryMode == .always)
    #expect(saved?.remembersPeople == true)
    #expect(await spy.roomIDs == [testGroupRoom.id])
    #expect(await sender.sent.first?.text.contains("프리셋 '풀'") == true)
}

@Test
func anUnknownPresetNameIsRefusedWithTheMenu() async {
    let (handler, sender, _) = makeHandler(
        adminRooms: [testGroupRoom.id],
        messagesByRoom: line("!프리셋 2 없는거"),
        policies: [RoomPolicy(accountFingerprint: testAccount.fingerprint, chatRoomID: testGroupRoom.id, responseMode: .off)]
    )

    _ = await handler.handle(roomID: testGroupRoom.id, account: testAccount)

    #expect(await sender.sent.first?.text.contains("그런 프리셋이 없어요") == true)
}
