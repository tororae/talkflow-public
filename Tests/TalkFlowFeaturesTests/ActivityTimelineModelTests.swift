import Foundation
import Testing
import TalkFlowApplication
import TalkFlowDomain
@testable import TalkFlowFeatures

@MainActor
private func makeModel(
    log: FakeActionLog,
    sender: FakeMessageSender = FakeMessageSender(),
    status: KakaoConnectionStatus = .connected(account: testAccount),
    usePolicyAccepted: Bool = true
) -> ActivityTimelineModel {
    ActivityTimelineModel(
        log: log,
        reviewDrafts: ReviewDrafts(
            actionLog: log,
            settingsStore: FakeSettingsStore(usePolicyAccepted: usePolicyAccepted),
            connection: FakeKakaoConnection(statusValue: status),
            sender: sender
        )
    )
}

@MainActor
@Test
func reloadingMarksUnresolvedDraftsAsWaiting() async {
    let log = FakeActionLog([
        testDraft(id: 1, minutesAgo: 2),
        testAction(id: 2, kind: .sent, replyText: "이미 보냄", minutesAgo: 1)
    ])
    let model = makeModel(log: log)

    await model.reload()

    #expect(model.actions.map(\.id) == [2, 1])
    #expect(model.pendingDraftIDs == [1])
    #expect(model.pendingSummary == "검토 대기 1건")
    #expect(model.summary == "전체 2건")
}

@Test
@MainActor
func nothingWaitingLeavesTheCountOffTheScreen() async {
    let model = makeModel(log: FakeActionLog([testAction(id: 1, kind: .held)]))

    await model.reload()

    #expect(model.pendingSummary == nil)
}

/// The reply pipeline reloads this screen on every KakaoTalk sync. Reassigning
/// the edit buffer there threw away whatever the user was part-way through
/// typing, which is the one thing this screen exists to let them do.
@MainActor
@Test
func aBackgroundReloadDoesNotDisturbAnEditInProgress() async {
    let log = FakeActionLog([testDraft(id: 1, replyText: "곧 도착해요")])
    let model = makeModel(log: log)
    await model.reload()
    model.select(id: 1)

    model.editedText = "조금 늦어요, 미안"
    try? await log.record(testAction(id: 99, kind: .held, roomID: "room-b"))
    await model.reload()

    #expect(model.editedText == "조금 늦어요, 미안")
    #expect(model.selectedActionID == 1)
    #expect(model.isEdited)
}

@MainActor
@Test
func choosingAnotherRowLoadsThatDraftIntoTheEditor() async {
    let log = FakeActionLog([
        testDraft(id: 1, replyText: "곧 도착해요", minutesAgo: 2),
        testDraft(id: 2, replyText: "내일 봬요", minutesAgo: 1)
    ])
    let model = makeModel(log: log)
    await model.reload()

    model.select(id: 1)
    #expect(model.editedText == "곧 도착해요")

    model.select(id: 2)
    #expect(model.editedText == "내일 봬요")
    #expect(model.isEdited == false)
}

/// This table is the only way to reach a draft now, so one older than the
/// history window still has to appear in it.
@MainActor
@Test
func aDraftOlderThanTheHistoryWindowIsStillReachable() async {
    let recent = (1...ActivityTimelineModel.historyLimit).map { index in
        testAction(id: Int64(index) + 1000, kind: .sent, replyText: "보냄", minutesAgo: index)
    }
    let old = testDraft(id: 7, replyText: "묵은 초안", minutesAgo: 5_000)
    let model = makeModel(log: FakeActionLog(recent + [old]))

    await model.reload()

    #expect(model.actions.count == ActivityTimelineModel.historyLimit + 1)
    #expect(model.actions.last?.id == 7)
    #expect(model.pendingDraftIDs == [7])
}

@MainActor
@Test
func sendingTheSelectedDraftDeliversTheEditedTextAndResolvesIt() async {
    let log = FakeActionLog([testDraft(id: 1, replyText: "곧 도착해요")])
    let sender = FakeMessageSender()
    let model = makeModel(log: log, sender: sender)
    await model.reload()
    model.select(id: 1)
    model.editedText = "10분만요"

    await model.sendSelected()

    #expect(await sender.sent.map(\.text) == ["10분만요"])
    #expect(model.pendingDraftIDs.isEmpty)
    #expect(model.actionFailure == nil)
    #expect(model.sendingID == nil)
}

@MainActor
@Test
func dismissingTheSelectedDraftSendsNothingAndResolvesIt() async {
    let log = FakeActionLog([testDraft(id: 1)])
    let sender = FakeMessageSender()
    let model = makeModel(log: log, sender: sender)
    await model.reload()
    model.select(id: 1)

    await model.dismissSelected()

    #expect(await sender.sent.isEmpty)
    #expect(model.pendingDraftIDs.isEmpty)
}

/// A failed send is recorded rather than consuming the draft, so the row stays
/// in the table to be tried again once whatever was in the way has passed.
@MainActor
@Test
func aFailedSendKeepsTheDraftWaitingAndSaysWhy() async {
    let log = FakeActionLog([testDraft(id: 1)])
    let model = makeModel(
        log: log,
        sender: FakeMessageSender(
            failure: MessageSendFailure(message: "카카오톡이 Enter를 받지 않았습니다.", isRetryable: true)
        )
    )
    await model.reload()
    model.select(id: 1)

    await model.sendSelected()

    #expect(model.actionFailure == "카카오톡이 Enter를 받지 않았습니다.")
    #expect(model.pendingDraftIDs == [1])
    #expect(model.actions.contains { $0.kind == .failed })
}

/// Working through a backlog should not mean hunting for the next draft among
/// everything else the table holds.
@MainActor
@Test
func decidingOnOneDraftSelectsTheNextOneWaiting() async {
    let log = FakeActionLog([
        testDraft(id: 1, replyText: "먼저", minutesAgo: 1),
        testDraft(id: 2, replyText: "다음", minutesAgo: 2)
    ])
    let model = makeModel(log: log)
    await model.reload()
    model.select(id: 1)

    await model.dismissSelected()

    #expect(model.selectedActionID == 2)
    #expect(model.editedText == "다음")
}

@MainActor
@Test
func aRefusedConnectionBlocksTheSendWithoutLosingTheDraft() async {
    let log = FakeActionLog([testDraft(id: 1)])
    let sender = FakeMessageSender()
    let model = makeModel(log: log, sender: sender, status: .unavailable(reason: "확인 실패"))
    await model.reload()
    model.select(id: 1)

    await model.sendSelected()

    #expect(await sender.sent.isEmpty)
    #expect(model.pendingDraftIDs == [1])
    #expect(model.actionFailure != nil)
}

@MainActor
@Test
func theUsePolicyIsReadOnEveryReload() async {
    let model = makeModel(log: FakeActionLog([testDraft(id: 1)]), usePolicyAccepted: false)

    await model.reload()

    #expect(model.usePolicyAccepted == false)
}

@MainActor
@Test
func filteringNarrowsTheTableAndSaysHowMuchIsHidden() async {
    let log = FakeActionLog([
        testDraft(id: 1, roomID: "room-a", roomName: "가족"),
        testAction(id: 2, kind: .sent, roomID: "room-b", roomName: "프로젝트 팀", replyText: "보냄"),
        testAction(id: 3, kind: .failed, roomID: "room-b", roomName: "프로젝트 팀")
    ])
    let model = makeModel(log: log)
    await model.reload()

    model.filter.setCategory(.failed, included: false)
    #expect(model.visibleRows.map(\.id).sorted() == [1, 2])

    model.setRoom("room-b", included: false)
    #expect(model.visibleRows.map(\.id) == [1])
    #expect(model.summary == "표시 1건 / 전체 3건")
}

/// The popover offers the rooms that have history, not every room in KakaoTalk,
/// so unticking one of them cannot leave a room the user never saw hidden.
@MainActor
@Test
func theRoomFilterOffersOnlyRoomsWithHistory() async {
    let log = FakeActionLog([
        testAction(id: 1, kind: .sent, roomID: "room-a", roomName: "가족", replyText: "보냄"),
        testAction(id: 2, kind: .held, roomID: "room-a", roomName: "가족")
    ])
    let model = makeModel(log: log)
    await model.reload()

    #expect(model.roomOptions.map(\.id) == ["room-a"])

    model.setRoom("room-a", included: false)
    #expect(model.visibleRows.isEmpty)

    model.setRoom("room-a", included: true)
    #expect(model.filter.roomIDs == nil)
    #expect(model.visibleRows.count == 2)
}

/// The most recent page is all that loads at first; 「더 보기」 reaches the history
/// behind it. Without this the table stopped at the last 200 events — a few hours
/// on a busy account — and everything older was simply unreachable.
@MainActor
@Test
func loadingMoreReachesHistoryBehindTheFirstPage() async {
    let total = ActivityTimelineModel.pageSize + 30
    let log = FakeActionLog((1...total).map { index in
        testAction(id: Int64(index), kind: .sent, replyText: "보냄", minutesAgo: total - index)
    })
    let model = makeModel(log: log)

    await model.reload()
    #expect(model.actions.count == ActivityTimelineModel.pageSize)
    #expect(model.canLoadMore)

    await model.loadMore()
    #expect(model.actions.count == total)
    #expect(!model.canLoadMore)
}

/// A record smaller than a page fits in the first read, so there is nothing
/// behind it and the 「더 보기」 button stays hidden.
@MainActor
@Test
func aRecordSmallerThanAPageHasNothingMoreToLoad() async {
    let model = makeModel(log: FakeActionLog([
        testAction(id: 1, kind: .sent, replyText: "보냄", minutesAgo: 2),
        testAction(id: 2, kind: .sent, replyText: "보냄", minutesAgo: 1)
    ]))

    await model.reload()

    #expect(!model.canLoadMore)
}

/// A 전송 record keeps neither the run nor the original message it answered — the
/// draft it came from does. Selecting the sent row still has to show what it
/// replied to, gathered from the draft in the same group; read off the sent event
/// alone it would show nothing, which is what left transfers looking like replies
/// to no one.
@MainActor
@Test
func aSentRecordShowsTheOriginalGatheredFromItsDraft() async {
    let log = FakeActionLog([
        testAction(id: 1, kind: .drafted, triggerMessageID: "m1", replyText: "곧 가요"),
        // 전송 이벤트는 원문도 답한 대화도 들고 있지 않다. 초안이 들고 있다.
        testAction(id: 2, kind: .sent, triggerMessageID: "m1", triggerText: nil, replyText: "곧 가요")
    ])
    let model = makeModel(log: log)
    await model.reload()
    model.select(id: 2)

    let section = model.answeredSection(for: model.selectedAction!, voice: .recorded)
    guard case .triggerOnly(let line)? = section?.body else {
        Issue.record("전송 레코드에서 원문을 가져오지 못했습니다: \(String(describing: section))")
        return
    }
    #expect(line.contains("언제 와?"))
}

/// A 전송 record does not store what triggered it — a mention, a direct message,
/// or a group the account joined on its own; the draft does. Selecting the sent
/// row still has to report the trigger, gathered from the draft in its group, so
/// 답장 and 멘션 can be told apart from the plain 일반 호출 that carries no badge.
@MainActor
@Test
func theSentRecordReportsWhatTriggeredItFromItsDraft() async {
    let log = FakeActionLog([
        testAction(id: 1, kind: .drafted, triggerMessageID: "m1", replyMode: .mention, replyText: "네"),
        testAction(id: 2, kind: .sent, triggerMessageID: "m1", triggerText: nil, replyText: "네")
    ])
    let model = makeModel(log: log)
    await model.reload()
    model.select(id: 2)

    #expect(model.replyTrigger(for: model.selectedAction!) == .mention)
}
