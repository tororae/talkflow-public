import Testing
import TalkFlowDomain

private func parse(_ text: String) -> AdminCommand? {
    AdminCommandParser.parse(text)
}

@Test
func helpAnswersToItsAliasesIncludingQuestionMark() {
    #expect(parse("!?") == .help)
    #expect(parse("!도움") == .help)
    #expect(parse("!help") == .help)
    #expect(parse("  !HELP  ") == .help)
}

@Test
func roomsListsOrSearchesByName() {
    #expect(parse("!방") == .rooms(filter: nil))
    #expect(parse("!rooms") == .rooms(filter: nil))
    #expect(parse("!방 가족") == .rooms(filter: "가족"))
    #expect(parse("!방 우리 가족 방") == .rooms(filter: "우리 가족 방"))
}

@Test
func aNumberOpensTheRoomAndAFieldAfterItDrillsIn() {
    #expect(parse("!방 3") == .room(number: 3))
    #expect(parse("!방 12") == .room(number: 12))
    // A trailing word that names no field is still ignored — just opens the room.
    #expect(parse("!방 3 세팅") == .room(number: 3))
    // A settable field drills into it, the same detail !세팅 3 전송 gives.
    #expect(parse("!방 3 전송") == .settingField(roomNumber: 3, field: "전송"))
    #expect(parse("!방 3 응답") == .settingField(roomNumber: 3, field: "응답"))
}

@Test
func usersTakesRoomThenMemberNumbers() {
    #expect(parse("!유저") == .users(roomNumber: nil))
    #expect(parse("!멤버") == .users(roomNumber: nil))
    #expect(parse("!유저 3") == .users(roomNumber: 3))
    #expect(parse("!유저 3 2") == .member(roomNumber: 3, memberNumber: 2))
}

@Test
func usersRejectsNonNumberSelectors() {
    #expect(parse("!유저 가족") == nil)
    #expect(parse("!유저 3 김철수") == nil)
}

@Test
func nonCommandsAndUnknownVerbsAreNothing() {
    #expect(parse("안녕하세요") == nil)
    #expect(parse("") == nil)
    #expect(parse("!") == nil)
    #expect(parse("! ") == nil)
    #expect(parse("!launch") == nil)
    #expect(parse("3/15 회의 잊지 마") == nil)
    // The prefix is ! now, so a line led by the old slash is just an ordinary
    // message — which is what stops the console echoing its own replies.
    #expect(parse("/방") == nil)
    #expect(parse("/세팅 2 응답 자동") == nil)
}

@Test
func settingTakesRoomFieldAndValue() {
    #expect(parse("!세팅 2 응답 자동") == .setting(roomNumber: 2, field: "응답", value: "자동"))
    #expect(parse("!설정 2 응답 자동") == .setting(roomNumber: 2, field: "응답", value: "자동"))
    // 값의 남은 단어는 이어붙는다 — 활성시간이 공백째 들어와도 살아남게.
    #expect(parse("!세팅 3 활성시간 09:00 - 23:00") == .setting(roomNumber: 3, field: "활성시간", value: "09:00 - 23:00"))
}

@Test
func presetAppliesWithANameOrListsWithout() {
    #expect(parse("!프리셋 3 풀") == .presetApply(roomNumber: 3, name: "풀"))
    #expect(parse("!preset 2 조용히") == .presetApply(roomNumber: 2, name: "조용히"))
    #expect(parse("!프리셋 3") == .presetList(roomNumber: 3))
    #expect(parse("!프리셋") == .presetList(roomNumber: nil))
}

@Test
func toggleTakesARoomNumberAndActivityIsAllRoomsOrOne() {
    #expect(parse("!켬 3") == .toggleRoom(roomNumber: 3, on: true))
    #expect(parse("!끔 3") == .toggleRoom(roomNumber: 3, on: false))
    #expect(parse("!on 3") == .toggleRoom(roomNumber: 3, on: true))
    #expect(parse("!켬") == nil)              // 방 번호 없으면 명령 아님
    #expect(parse("!활동") == .activity(roomNumber: nil, page: 1))
    #expect(parse("!활동 3") == .activity(roomNumber: 3, page: 1))
    #expect(parse("!기록 3") == .activity(roomNumber: 3, page: 1))
    #expect(parse("!활동 전체") == .activity(roomNumber: nil, page: 1))   // 숫자 아니면 전체
}

@Test
func activityDrillsWithABareNumberAndPagesWithAJjok() {
    #expect(parse("!활동 3 5") == .activityDetail(roomNumber: 3, itemNumber: 5))   // 상세
    #expect(parse("!활동 3 2쪽") == .activity(roomNumber: 3, page: 2))              // 페이지
    #expect(parse("!활동 3 2페이지") == .activity(roomNumber: 3, page: 2))
    #expect(parse("!활동 2쪽") == .activity(roomNumber: nil, page: 2))             // 전체 2쪽
}

@Test
func settingRevealsItselfAStepAtATime() {
    #expect(parse("!세팅") == .settingUsage)                     // 아무것도 → 사용법
    #expect(parse("!세팅 응답 자동") == .settingUsage)            // 방 번호가 숫자 아님 → 사용법
    #expect(parse("!세팅 2") == .settingFields(roomNumber: 2))                // 방만 → 항목 목록
    #expect(parse("!세팅 2 응답") == .settingField(roomNumber: 2, field: "응답")) // 방+항목 → 값 목록
    #expect(parse("!세팅 2 응답 자동") == .setting(roomNumber: 2, field: "응답", value: "자동"))
}
