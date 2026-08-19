import Testing
import TalkFlowDomain
@testable import TalkFlowFeatures

private let everyKind: [AgentAction] = [
    testAction(id: 1, kind: .held),
    testAction(id: 2, kind: .drafted, replyText: "곧 도착해요"),
    testAction(id: 3, kind: .sent, replyText: "곧 도착해요"),
    testAction(id: 4, kind: .failed),
    testAction(id: 5, kind: .dismissed)
]

@Test
func aFreshFilterHidesNothing() {
    let filter = ActivityFilter()

    #expect(filter.apply(to: ActivityRow.rows(from: everyKind)).count == everyKind.count)
    #expect(filter.isNarrowed == false)
    #expect(filter.roomSummary == "채팅방 전체")
}

@Test
func untickingACategoryDropsOnlyThatKind() {
    var filter = ActivityFilter()
    filter.setCategory(.sent, included: false)

    #expect(filter.apply(to: ActivityRow.rows(from: everyKind)).map(\.id) == [1, 2, 4, 5])
    #expect(filter.isNarrowed)
}

/// 무시함 has no box of its own; it rides with 보류, because both mean nothing
/// was sent and somebody decided that on purpose.
@Test
func aHoldAndADismissedDraftShareOneCheckbox() {
    var filter = ActivityFilter()
    filter.categories = [.held]

    #expect(filter.apply(to: ActivityRow.rows(from: everyKind)).map(\.id) == [1, 5])
}

@Test
func untickingEveryCategoryShowsNothingRatherThanEverything() {
    var filter = ActivityFilter()
    for category in ActivityFilter.Category.allCases {
        filter.setCategory(category, included: false)
    }

    #expect(filter.apply(to: ActivityRow.rows(from: everyKind)).isEmpty)
}

private let rooms = ["room-a", "room-b", "room-c"]

private let inThreeRooms: [AgentAction] = [
    testAction(id: 1, kind: .sent, roomID: "room-a", roomName: "가족"),
    testAction(id: 2, kind: .sent, roomID: "room-b", roomName: "프로젝트 팀"),
    testAction(id: 3, kind: .sent, roomID: "room-c", roomName: "동아리")
]

@Test
func turningOneRoomOffKeepsTheRest() {
    var filter = ActivityFilter()
    filter.setRoom("room-b", included: false, amongst: rooms)

    #expect(filter.apply(to: ActivityRow.rows(from: inThreeRooms)).map(\.id) == [1, 3])
    #expect(filter.roomSummary == "채팅방 2개")
}

/// A room whose first message arrives tomorrow must not be filtered out by a
/// choice made today, so "every room" stays "every room" rather than becoming a
/// list of the ids that existed when it was ticked.
@Test
func tickingTheLastRoomBackOnReturnsToEveryRoom() {
    var filter = ActivityFilter()
    filter.setRoom("room-b", included: false, amongst: rooms)
    filter.setRoom("room-b", included: true, amongst: rooms)

    #expect(filter.roomIDs == nil)
    #expect(filter.includesRoom("room-d"))
}

@Test
func selectAllRoomsAlsoIncludesRoomsNotSeenYet() {
    var filter = ActivityFilter()
    filter.clearRooms()
    filter.selectAllRooms()

    #expect(filter.roomIDs == nil)
    #expect(filter.includesRoom("room-d"))
}

/// Clearing exists so a couple of rooms can be picked out of thirty without
/// unticking the other twenty-eight.
@Test
func clearingRoomsLeavesNothingSelected() {
    var filter = ActivityFilter()
    filter.clearRooms()

    #expect(filter.apply(to: ActivityRow.rows(from: inThreeRooms)).isEmpty)
    #expect(filter.roomSummary == "채팅방 없음")

    filter.setRoom("room-c", included: true, amongst: rooms)
    #expect(filter.apply(to: ActivityRow.rows(from: inThreeRooms)).map(\.id) == [3])
}

@Test
func categoryAndRoomNarrowTogether() {
    var filter = ActivityFilter()
    filter.setCategory(.sent, included: false)
    filter.setRoom("room-a", included: false, amongst: rooms)

    let actions = [
        testAction(id: 1, kind: .sent, roomID: "room-b"),
        testAction(id: 2, kind: .failed, roomID: "room-a"),
        testAction(id: 3, kind: .failed, roomID: "room-b")
    ]
    #expect(filter.apply(to: ActivityRow.rows(from: actions)).map(\.id) == [3])
}

@Test
func roomOptionsCountEachRoomOnceAndSortByName() {
    let options = ActivityRoomOption.options(from: [
        testAction(id: 1, kind: .sent, roomID: "room-b", roomName: "프로젝트 팀"),
        testAction(id: 2, kind: .held, roomID: "room-a", roomName: "가족"),
        testAction(id: 3, kind: .failed, roomID: "room-a", roomName: "가족")
    ])

    #expect(options.map(\.name) == ["가족", "프로젝트 팀"])
    #expect(options.map(\.count) == [2, 1])
}

/// A room the archive no longer names still has to be pickable, so the id
/// stands in for the label rather than leaving a blank line in the popover.
@Test
func aRoomWithNoNameIsListedByItsID() {
    let options = ActivityRoomOption.options(from: [
        testAction(id: 1, kind: .sent, roomID: "room-z", roomName: "")
    ])

    #expect(options.map(\.name) == ["room-z"])
}

// MARK: - 먼저 말 걸기

/// The only rows on this screen TalkFlow wrote with nobody having asked. Folding
/// them into 초안 would make the one thing worth checking on findable only by
/// reading every row.
@Test
func anOpenerHasItsOwnBoxRatherThanRidingWithTheDrafts() {
    let rows = everyKind + [testAction(id: 6, kind: .opened, replyText: "그거 결국 어떻게 됐어요?")]
    var drafts = ActivityFilter()
    drafts.categories = [.drafted]
    var openers = ActivityFilter()
    openers.categories = [.opened]

    #expect(ActivityFilter().apply(to: ActivityRow.rows(from: rows)).count == rows.count)
    #expect(drafts.apply(to: ActivityRow.rows(from: rows)).map(\.id) == [2])
    #expect(openers.apply(to: ActivityRow.rows(from: rows)).map(\.id) == [6])
}

/// Both outcomes wear the same tick box. "무엇을 먼저 말했나" is one question, and
/// an opener the model passed on is part of the answer.
@Test
func anOpenerTheModelPassedOnIsFiledWithTheOnesItWrote() {
    let rows = [
        testAction(id: 1, kind: .opened, replyText: "그거 결국 어떻게 됐어요?"),
        testAction(id: 2, kind: .opened)
    ]
    var openers = ActivityFilter()
    openers.categories = [.opened]

    #expect(openers.apply(to: ActivityRow.rows(from: rows)).map(\.id) == [1, 2])
}

/// The column has to say what happened. "먼저 말 걸기" on a row with no text reads
/// as a message that went out.
@Test
func anOpenerRowSaysWhetherAnythingWasActuallySaid() {
    let spoke = testAction(id: 1, kind: .opened, replyText: "그거 결국 어떻게 됐어요?")
    let passed = testAction(id: 2, kind: .opened)

    #expect(ActivityKindStyle.title(for: spoke, isPending: false) == "먼저 말 걸기")
    #expect(ActivityKindStyle.title(for: spoke, isPending: true) == "검토 대기")
    #expect(ActivityKindStyle.title(for: passed, isPending: false) == "말 걸지 않음")
}

// MARK: - 관리자 명령 (콘솔)

/// 관리자 명령 rows ride their own switch: hidden by default and shown only when the
/// 「관리자」 box is on — never pulled in by 보냄 nor swept by 전체 선택.
@Test
func adminCommandsAreHiddenByDefaultAndShownOnlyOnTheirOwnBox() {
    let rows = everyKind + [testAction(id: 6, kind: .commanded, replyText: "관리자 명령에 답했습니다.")]

    // Default: the five message rows, not the 관리자 명령.
    #expect(ActivityFilter().apply(to: ActivityRow.rows(from: rows)).map(\.id) == [1, 2, 3, 4, 5])

    var showing = ActivityFilter()
    showing.setShowsCommands(true)
    #expect(showing.apply(to: ActivityRow.rows(from: rows)).map(\.id) == [1, 2, 3, 4, 5, 6])
}

/// 전체 선택/해제 move only 결과·단계; the 관리자 box keeps its own state either way,
/// so turning everything on does not surface a runaway console by surprise, and
/// clearing the message boxes does not hide the commands somebody was reading.
@Test
func selectAllAndClearAllLeaveTheAdminCommandBoxAlone() {
    let rows = everyKind + [testAction(id: 6, kind: .commanded)]
    var filter = ActivityFilter()
    filter.setShowsCommands(true)

    filter.clearAll()
    #expect(filter.showsCommands)
    // 메시지 축은 비었어도 관리자 명령은 자기 스위치로 남는다.
    #expect(filter.apply(to: ActivityRow.rows(from: rows)).map(\.id) == [6])

    filter.selectAll()
    #expect(filter.showsCommands)
}

/// 전체 선택/해제 must not reach the room filter — one button silently undoing a
/// room choice somebody set on purpose is the bug being fixed.
@Test
func selectAllAndClearAllDoNotTouchTheRoomFilter() {
    var filter = ActivityFilter()
    filter.setRoom("room-b", included: false, amongst: rooms)
    #expect(filter.roomIDs != nil)

    filter.clearAll()
    #expect(filter.roomIDs != nil)
    #expect(filter.includesRoom("room-b") == false)

    filter.selectAll()
    #expect(filter.roomIDs != nil)
    #expect(filter.includesRoom("room-b") == false)
}
