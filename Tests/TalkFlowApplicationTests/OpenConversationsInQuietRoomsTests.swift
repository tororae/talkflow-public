import Foundation
import Testing
import TalkFlowDomain
@testable import TalkFlowApplication

private let now = Date(timeIntervalSince1970: 1_700_000_000)

/// The default, and the only behaviour anybody gets without going to look for
/// this. Not merely "no message" — no model call, and not even a read of the
/// conversation, because this sweep runs every ten seconds for as long as the app
/// is open.
@Test
func aRoomNobodySwitchedOnIsNeverEvenReadFor() async {
    let generator = FakeReplyGenerator()
    let connection = CountingKakaoConnection(messages: quietConversation())
    let sweep = makeSweep(
        connection: connection,
        policies: [enabledGroupPolicy()],
        generator: generator
    )

    let opened = await sweep(now: now)

    #expect(opened.isEmpty)
    #expect(await generator.callCount == 0)
    #expect(await connection.messageReads == 0)
}

@Test
func aQuietRoomThatHasWaitedItsTurnGetsAnOpener() async {
    let log = FakeActionLog()
    let sweep = makeSweep(
        policies: [openerPolicy()],
        log: log,
        generator: FakeReplyGenerator(
            draft: ReplyDraft(shouldReply: true, mode: .spontaneous, confidence: .medium, text: "그거 결국 어떻게 됐어요?")
        )
    )

    let opened = await sweep(now: now)

    #expect(opened.count == 1)
    #expect(opened.first?.kind == .opened)
    #expect(opened.first?.replyText == "그거 결국 어떻게 됐어요?")
    #expect(await log.recorded.count == 1)
}

/// The record has to say this was TalkFlow's own idea. A 촉발 메시지 or an answered
/// run beside it would read as a reply to the room's last message, which is the
/// one thing the timeline must not get wrong about this feature.
@Test
func theRecordCarriesNoTriggerAndNoAnsweredRun() async {
    let sweep = makeSweep(policies: [openerPolicy()])

    let action = await sweep(now: now).first

    #expect(action?.kind == .opened)
    #expect(action?.triggerText == nil)
    #expect(action?.triggerSenderName == nil)
    #expect(action?.triggerSenderID == nil)
    #expect(action?.answeredRun == nil)
    // Its own key rather than the room's newest message, so a reply waiting on
    // that message is neither resolved by this one nor resolves it.
    #expect(action?.triggerMessageID?.hasPrefix(ConversationOpenerKey.prefix) == true)
    #expect(action?.triggerMessageID != "m2")
}

/// "지금 꺼낼 만한 이야기 없음" is the right answer most of the time, and it is a
/// judgement the user paid for, so it is recorded with the model's own words.
@Test
func aModelThatDeclinesLeavesARowSayingWhy() async {
    let sweep = makeSweep(
        policies: [openerPolicy()],
        generator: FakeReplyGenerator(
            draft: ReplyDraft(
                shouldReply: false,
                mode: .spontaneous,
                confidence: .low,
                text: nil,
                declineReason: "지난 대화가 이미 마무리돼 이어 갈 말이 없음"
            )
        )
    )

    let action = await sweep(now: now).first

    #expect(action?.kind == .opened)
    #expect(action?.replyText == nil)
    #expect(action?.detail.contains("지난 대화가 이미 마무리돼 이어 갈 말이 없음") == true)
}

/// Agreeing that TalkFlow may answer for you is not agreeing that it may speak
/// for you, so a room delivering replies on its own still only drafts an opener.
@Test
func aRoomThatSendsItsRepliesAutomaticallyStillOnlyDraftsAnOpener() async {
    let sendStore = FakeSendStore()
    var policy = openerPolicy()
    policy.deliveryMode = .always
    policy.conversationOpener = .draftOnly
    let sweep = makeSweep(policies: [policy], sendStore: sendStore)

    let action = await sweep(now: now).first

    #expect(action?.kind == .opened)
    #expect(action?.replyText != nil)
    #expect(await sendStore.queued.isEmpty)
    #expect(action?.detail.contains("검토가 필요합니다") == true)
}

/// The second, separate choice. It needs both: this one, and the room's own
/// 전송 방식 — which it can never be more permissive than.
@Test
func deliveryNeedsBothChoicesAndCarriesTheSilenceItWasWrittenFor() async {
    let queued = FakeSendStore()
    let blocked = FakeSendStore()

    var delivering = openerPolicy()
    delivering.deliveryMode = .always
    delivering.conversationOpener = .delivers
    await makeSweep(policies: [delivering], sendStore: queued)(now: now)

    var draftingRoom = delivering
    draftingRoom.deliveryMode = .draftOnly
    await makeSweep(policies: [draftingRoom], sendStore: blocked)(now: now)

    #expect(await queued.queued.count == 1)
    #expect(await queued.queued.first?.opensConversationAfterMessageID == "m2")
    #expect(await blocked.queued.isEmpty)
}

@Test
func theGlobalPauseStopsTheSweepBeforeAnyModelCall() async {
    let generator = FakeReplyGenerator()
    let sweep = makeSweep(
        policies: [openerPolicy()],
        settings: FakeSettingsStore(enabled: false),
        generator: generator
    )

    #expect(await sweep(now: now).isEmpty)
    #expect(await generator.callCount == 0)
}

@Test
func anUnverifiedAccountStopsTheSweepBeforeAnyModelCall() async {
    let generator = FakeReplyGenerator()
    let sweep = OpenConversationsInQuietRooms(
        connection: FakeKakaoConnection(
            status: .unavailable(reason: "계정 확인 실패"),
            rooms: [testGroupRoom],
            messagesByRoom: [testGroupRoom.id: quietConversation()]
        ),
        policyStore: FakePolicyStore([openerPolicy()]),
        settingsStore: FakeSettingsStore(),
        actionLog: FakeActionLog(),
        generator: generator
    )

    #expect(await sweep(now: now).isEmpty)
    #expect(await generator.callCount == 0)
}

/// Opening a subject while people are talking is interrupting, not opening.
@Test
func aRoomThatIsStillTalkingIsLeftAlone() async {
    let generator = FakeReplyGenerator()
    let sweep = makeSweep(
        messages: quietConversation(lastMessageAgo: 300),
        policies: [openerPolicy()],
        generator: generator
    )

    #expect(await sweep(now: now).isEmpty)
    #expect(await generator.callCount == 0)
}

/// Waiting out the interval is the normal state and happens every ten seconds
/// for hours. Recording it would bury the rows a person has to act on.
@Test
func waitingForItsTurnLeavesNoRowBehind() async {
    let log = FakeActionLog()
    var policy = openerPolicy()
    policy.conversationOpenerInterval = JudgementInterval(fixed: 21600)
    let sweep = makeSweep(policies: [policy], log: log)

    #expect(await sweep(now: now).isEmpty)
    #expect(await log.recorded.isEmpty)
}

/// The record of the call is what starts the next cycle, so a second sweep a
/// moment later costs nothing. Without that the sweep would ask again on every
/// poll for as long as the room stayed quiet.
@Test
func aRoomIsNotOpenedTwiceInOneCycle() async {
    let generator = FakeReplyGenerator()
    let sweep = makeSweep(policies: [openerPolicy()], log: FakeActionLog(), generator: generator)

    await sweep(now: now)
    await sweep(now: now.addingTimeInterval(10))

    #expect(await generator.callCount == 1)
}

@Test
func aFailedOpenerCallIsRecordedInsteadOfSwallowed() async {
    let sweep = makeSweep(policies: [openerPolicy()], generator: FakeReplyGenerator(draft: nil))

    let action = await sweep(now: now).first

    #expect(action?.kind == .failed)
    #expect(action?.detail.contains("Codex") == true)
    // Still counted as a call, or a failing provider would be asked again every
    // ten seconds for as long as the room stayed quiet.
    #expect((action?.contextMessageCount ?? 0) > 0)
}

@Test
func theModelIsAskedToOpenRatherThanToReply() async {
    let generator = FakeReplyGenerator()
    let sweep = makeSweep(policies: [openerPolicy()], generator: generator)

    await sweep(now: now)

    #expect(await generator.lastRequest?.intent == .openConversation)
    #expect(await generator.lastRequest?.recentMessages.count == 2)
}

// MARK: - ②연속 횟수

/// TalkFlow spoke last and nobody has answered, but the room allows two openers in
/// a row and only one has gone out — counted off the log since the other side's
/// last message — so the second is allowed.
@Test
func talkFlowOpensAgainWhileInsideItsRepeatRun() async {
    var policy = openerPolicy()
    policy.openerRepeatLimit = 2
    let log = FakeActionLog(existing: [priorOpener(at: now.addingTimeInterval(-7000))])
    let sweep = makeSweep(
        messages: conversationTalkFlowSpokeLastIn(),
        policies: [policy],
        log: log
    )

    let opened = await sweep(now: now)

    #expect(opened.count == 1)
    #expect(opened.first?.kind == .opened)
}

/// The same room once both of its allowed openers have gone out with no answer:
/// the count off the log has reached the limit, so it holds rather than talk to
/// itself a third time — and does not even spend the model call to find that out.
@Test
func talkFlowStopsOnceItHasUsedUpItsRepeatRun() async {
    var policy = openerPolicy()
    policy.openerRepeatLimit = 2
    let generator = FakeReplyGenerator()
    let log = FakeActionLog(existing: [
        priorOpener(at: now.addingTimeInterval(-7000)),
        priorOpener(at: now.addingTimeInterval(-6800))
    ])
    let sweep = makeSweep(
        messages: conversationTalkFlowSpokeLastIn(),
        policies: [policy],
        log: log,
        generator: generator
    )

    #expect(await sweep(now: now).isEmpty)
    #expect(await generator.callCount == 0)
}

/// A repeat opener hands the room's standing hint and its 재시도 주제 to the prompt,
/// and flags itself a repeat so the prompt knows not to treat it as a first
/// opening.
@Test
func aRepeatOpenerCarriesTheRoomsHintAndRetryTopicIntoTheRequest() async {
    var policy = openerPolicy()
    policy.openerRepeatLimit = 2
    policy.openerPromptHint = "요즘 하는 프로젝트 얘기 꺼내"
    policy.openerRepeatTopic = .fresh
    let generator = FakeReplyGenerator()
    let log = FakeActionLog(existing: [priorOpener(at: now.addingTimeInterval(-7000))])
    let sweep = makeSweep(
        messages: conversationTalkFlowSpokeLastIn(),
        policies: [policy],
        log: log,
        generator: generator
    )

    await sweep(now: now)

    #expect(await generator.lastRequest?.openerHint == "요즘 하는 프로젝트 얘기 꺼내")
    #expect(await generator.lastRequest?.isRepeatOpener == true)
    #expect(await generator.lastRequest?.openerRepeatTopic == .fresh)
}

/// A first opener — the other side spoke last — is not a repeat, so its request
/// says so however the room's 재시도 주제 is set.
@Test
func aFirstOpenerIsNotFlaggedAsARepeat() async {
    var policy = openerPolicy()
    policy.openerRepeatTopic = .fresh
    let generator = FakeReplyGenerator()
    let sweep = makeSweep(policies: [policy], generator: generator)

    await sweep(now: now)

    #expect(await generator.lastRequest?.isRepeatOpener == false)
    #expect(await generator.lastRequest?.openerHint == nil)
}

// MARK: - Fixtures

/// A group room where TalkFlow itself said the last thing, two hours ago, after
/// the other side's word an hour before that — the shape a repeat opener reads.
private func conversationTalkFlowSpokeLastIn() -> [ChatMessage] {
    [
        testMessage(
            id: "m1",
            roomID: testGroupRoom.id,
            body: "그건 다음 주에 정하기로 했었죠",
            sentAt: now.addingTimeInterval(-7260)
        ),
        testMessage(
            id: "m2",
            roomID: testGroupRoom.id,
            body: "그때 그거 결국 어떻게 됐어요?",
            isFromMe: true,
            sentAt: now.addingTimeInterval(-7200)
        )
    ]
}

/// An opener already on the log, dated after the other side's last message so it
/// falls inside the run `openerCount` measures.
private func priorOpener(at date: Date) -> AgentAction {
    AgentAction(
        accountFingerprint: testAccount.fingerprint,
        chatRoomID: testGroupRoom.id,
        kind: .opened,
        triggerMessageID: ConversationOpenerKey.make(),
        replyText: "그거 어떻게 됐어요?",
        detail: "먼저 말 걸 내용을 만들었습니다.",
        contextMessageCount: 2,
        createdAt: date
    )
}

/// A group room two hours past its last word, which is what "quiet" means here.
private func quietConversation(lastMessageAgo: TimeInterval = 7200) -> [ChatMessage] {
    [
        testMessage(
            id: "m1",
            roomID: testGroupRoom.id,
            body: "그건 다음 주에 정하기로 했었죠",
            sentAt: now.addingTimeInterval(-lastMessageAgo - 60)
        ),
        testMessage(
            id: "m2",
            roomID: testGroupRoom.id,
            body: "네 그때 봐요",
            sentAt: now.addingTimeInterval(-lastMessageAgo)
        )
    ]
}

/// Answering enabled, opening not. The state every room is in until somebody
/// changes it.
private func enabledGroupPolicy() -> RoomPolicy {
    RoomPolicy(
        accountFingerprint: testAccount.fingerprint,
        chatRoomID: testGroupRoom.id,
        responseMode: .automatic,
        deliveryMode: .always,
        minimumInterval: 0
    )
}

private func openerPolicy() -> RoomPolicy {
    var policy = enabledGroupPolicy()
    policy.deliveryMode = .draftOnly
    policy.conversationOpener = .draftOnly
    policy.conversationOpenerInterval = JudgementInterval(fixed: 3600)
    return policy
}

private func makeSweep(
    connection: (any KakaoConnection)? = nil,
    messages: [ChatMessage]? = nil,
    policies: [RoomPolicy],
    settings: FakeSettingsStore = FakeSettingsStore(),
    log: FakeActionLog = FakeActionLog(),
    generator: FakeReplyGenerator = FakeReplyGenerator(
        draft: ReplyDraft(shouldReply: true, mode: .spontaneous, confidence: .medium, text: "그거 결국 어떻게 됐어요?")
    ),
    sendStore: FakeSendStore? = nil
) -> OpenConversationsInQuietRooms {
    OpenConversationsInQuietRooms(
        connection: connection ?? FakeKakaoConnection(
            rooms: [testGroupRoom],
            messagesByRoom: [testGroupRoom.id: messages ?? quietConversation()]
        ),
        policyStore: FakePolicyStore(policies),
        settingsStore: settings,
        actionLog: log,
        generator: generator,
        sendStore: sendStore
    )
}

/// Counts reads of the conversation, which is what "costs nothing when nobody
/// asked for it" has to be measured against.
actor CountingKakaoConnection: KakaoConnection {
    private(set) var messageReads = 0
    private let messages: [ChatMessage]

    init(messages: [ChatMessage]) {
        self.messages = messages
    }

    func status() async -> KakaoConnectionStatus { .connected(account: testAccount) }
    func chatRooms() async throws -> [ChatRoom] { [testGroupRoom] }

    func recentMessages(in chatRoom: ChatRoom, limit: Int) async throws -> [ChatMessage] {
        messageReads += 1
        return Array(messages.suffix(limit))
    }
}
