import Foundation
import Testing
@testable import TalkFlowDomain

private let account = "katok-test"
private let groupRoom = ChatRoom(id: "room-g", displayName: "프로젝트 팀", kind: .group)
private let directRoom = ChatRoom(id: "room-d", displayName: "가족", kind: .direct)
private let engine = ResponsePolicyEngine()

@Test
func newRoomsAnswerNobodyUntilTheUserTurnsThemOn() {
    let policy = RoomPolicy.makeDefault(accountFingerprint: account, room: directRoom)

    #expect(policy.responseMode == .off)
    #expect(policy.deliveryMode == .draftOnly)
    #expect(engine.evaluate(request(room: directRoom, policy: policy)) == .hold(reason: .roomDisabled))
}

/// Typing `@이름` from outside KakaoTalk leaves text rather than a mention, so a
/// room tags only after the user decides it should. Hours start unlimited so
/// turning the setting on is the only thing that ever changes when a room may
/// answer.
@Test
func aNewRoomDoesNotLimitItsHoursOrClaimKeywords() {
    let policy = RoomPolicy.makeDefault(accountFingerprint: account, room: groupRoom)

    #expect(policy.activeHours == .always)
    #expect(policy.responseKeywords.isEmpty)
}

/// The whole point of detecting the name: a group room enabled with one switch,
/// with nothing typed into any keyword list anywhere, answers when someone calls
/// it by the name KakaoTalk already shows. Registering it was the step that
/// nobody knew to take, and a room set to `멘션에만 응답` sat silent because of it.
@Test
func aMentionOnlyRoomAnswersItsOwnNameWithNoKeywordsConfiguredAtAll() {
    let outcome = engine.evaluate(
        request(
            room: groupRoom,
            policy: policy(mode: .mentionOnly),
            messages: [message(id: "m1", body: "달구지톡 이거 확인 부탁해요")],
            accountNickname: "달구지톡",
            responseKeywords: []
        )
    )

    #expect(outcome == .ask(trigger: .mention, triggerMessageID: "m1"))
}

/// A word registered on one room is a call in that room and nowhere else.
@Test
func aRoomsOwnKeywordCallsItWithoutBeingRegisteredGlobally() {
    var withKeyword = policy(mode: .mentionOnly)
    withKeyword.responseKeywords = ["달빛"]

    let inThatRoom = engine.evaluate(
        request(
            room: groupRoom,
            policy: withKeyword,
            messages: [message(id: "m1", body: "달빛 오늘 일정 뭐야?")],
            responseKeywords: []
        )
    )
    let elsewhere = engine.evaluate(
        request(
            room: groupRoom,
            policy: policy(mode: .mentionOnly),
            messages: [message(id: "m1", body: "달빛 오늘 일정 뭐야?")],
            responseKeywords: []
        )
    )

    #expect(inThatRoom == .ask(trigger: .mention, triggerMessageID: "m1"))
    #expect(elsewhere == .hold(reason: .notAddressed))
}

/// The three sources are one set at evaluation time, and each of them alone is
/// enough to make a message a call.
@Test
func theNameAndBothKeywordListsAllCountAsBeingCalled() {
    var withKeyword = policy(mode: .mentionOnly)
    withKeyword.responseKeywords = ["달빛"]

    let outcomes = ["달구지톡 있어?", "달구봇 있어?", "달빛 있어?", "거기 누구 있어?"].map { body in
        engine.evaluate(
            request(
                room: groupRoom,
                policy: withKeyword,
                messages: [message(id: "m1", body: body)],
                accountNickname: "달구지톡",
                responseKeywords: ["달구봇"]
            )
        )
    }

    #expect(outcomes.prefix(3).allSatisfy { $0 == .ask(trigger: .mention, triggerMessageID: "m1") })
    #expect(outcomes.last == .hold(reason: .notAddressed))
}

@Test
func enablingAGroupRoomOnlyAnswersMentions() {
    #expect(RoomPolicy.initialEnabledMode(for: groupRoom) == .mentionOnly)
    #expect(RoomPolicy.initialEnabledMode(for: directRoom) == .automatic)
}

@Test
func globalPauseOutranksEveryRoomPolicy() {
    let outcome = engine.evaluate(
        request(
            room: directRoom,
            policy: policy(mode: .automatic),
            globalResponsesEnabled: false
        )
    )

    #expect(outcome == .hold(reason: .globalPause))
}

@Test
func anUnverifiedAccountStopsEvaluationBeforeAnyRoomRule() {
    let outcome = engine.evaluate(
        request(
            room: directRoom,
            policy: policy(mode: .automatic),
            accountVerified: false
        )
    )

    #expect(outcome == .hold(reason: .accountUnverified))
}

@Test
func detectOnlyRoomsRecordActivityWithoutAsking() {
    let outcome = engine.evaluate(request(room: groupRoom, policy: policy(mode: .detectOnly)))

    #expect(outcome == .hold(reason: .detectOnly))
}

@Test
func mentionOnlyRoomsIgnoreMessagesThatDoNotNameTheAccount() {
    let outcome = engine.evaluate(
        request(
            room: groupRoom,
            policy: policy(mode: .mentionOnly),
            messages: [message(id: "m1", body: "오늘 회의 몇 시죠?")]
        )
    )

    #expect(outcome == .hold(reason: .notAddressed))
}

@Test
func mentionOnlyRoomsAnswerWhenTheAccountIsNamed() {
    let outcome = engine.evaluate(
        request(
            room: groupRoom,
            policy: policy(mode: .mentionOnly),
            messages: [message(id: "m1", body: "@한결 이거 확인 부탁해요")]
        )
    )

    #expect(outcome == .ask(trigger: .mention, triggerMessageID: "m1"))
}

/// A keyword is a call sign rather than a mention entity. KakaoTalk's @-mention
/// is plain text by the time it reaches here, and people summon the account by
/// name without the @ just as often, so both count.
@Test
func keywordMatchingIgnoresCaseAndAcceptsCallsWithoutTheAtSign() {
    let tagged = engine.evaluate(
        request(
            room: groupRoom,
            policy: policy(mode: .mentionOnly),
            messages: [message(id: "m1", body: "@HANGYEOL 봐줄래?")],
            responseKeywords: ["hangyeol"]
        )
    )
    let called = engine.evaluate(
        request(
            room: groupRoom,
            policy: policy(mode: .mentionOnly),
            messages: [message(id: "m1", body: "hangyeol 봐줄래?")],
            responseKeywords: ["hangyeol"]
        )
    )
    let unrelated = engine.evaluate(
        request(
            room: groupRoom,
            policy: policy(mode: .mentionOnly),
            messages: [message(id: "m1", body: "이거 누가 확인했죠?")],
            responseKeywords: ["hangyeol"]
        )
    )

    #expect(tagged == .ask(trigger: .mention, triggerMessageID: "m1"))
    #expect(called == .ask(trigger: .mention, triggerMessageID: "m1"))
    #expect(unrelated == .hold(reason: .notAddressed))
}

@Test
func anyOneOfTheRegisteredKeywordsCountsAsBeingCalled() {
    let keywords = ["한결", "달구봇"]
    let first = engine.evaluate(
        request(
            room: groupRoom,
            policy: policy(mode: .mentionOnly),
            messages: [message(id: "m1", body: "@한결 이거 봐줘")],
            responseKeywords: keywords
        )
    )
    let second = engine.evaluate(
        request(
            room: groupRoom,
            policy: policy(mode: .mentionOnly),
            messages: [message(id: "m1", body: "달구봇 이거 봐줘")],
            responseKeywords: keywords
        )
    )

    #expect(first == .ask(trigger: .mention, triggerMessageID: "m1"))
    #expect(second == .ask(trigger: .mention, triggerMessageID: "m1"))
}

/// Korean particles attach straight onto the noun, so a keyword has to match
/// inside a word or half the ways people call the account would miss.
@Test
func aKeywordStillMatchesWithAParticleAttachedToIt() {
    let outcome = engine.evaluate(
        request(
            room: groupRoom,
            policy: policy(mode: .mentionOnly),
            messages: [message(id: "m1", body: "달구봇아 지금 뭐 해?")],
            responseKeywords: ["달구봇"]
        )
    )

    #expect(outcome == .ask(trigger: .mention, triggerMessageID: "m1"))
}

@Test
func directRoomsOnAutomaticAnswerWithoutBeingNamed() {
    let outcome = engine.evaluate(
        request(
            room: directRoom,
            policy: policy(mode: .automatic),
            messages: [message(id: "m1", body: "내일 시간 돼?")]
        )
    )

    #expect(outcome == .ask(trigger: .directQuestion, triggerMessageID: "m1"))
}

/// 0% keeps a message nobody addressed away from the model, and says so with a
/// reason of its own: a room the user dialled down and a room nobody spoke to
/// are different silences.
@Test
func groupRoomsOnAutomaticStaySilentWhileTheChanceIsZero() {
    let never = engine.evaluate(
        request(
            room: groupRoom,
            policy: policy(mode: .automatic, chance: .never),
            messages: [message(id: "m1", body: "다들 점심 뭐 먹어요?")]
        )
    )
    let always = engine.evaluate(
        request(
            room: groupRoom,
            policy: policy(mode: .automatic, chance: .always),
            messages: [message(id: "m1", body: "다들 점심 뭐 먹어요?")]
        )
    )

    #expect(never == .hold(reason: .interjectionSkipped))
    #expect(always == .ask(trigger: .spontaneous, triggerMessageID: "m1"))
}

@Test
func ownMessagesNeverTriggerAReply() {
    let outcome = engine.evaluate(
        request(
            room: directRoom,
            policy: policy(mode: .automatic),
            messages: [message(id: "m1", body: "내가 보낸 말", isFromMe: true)]
        )
    )

    #expect(outcome == .hold(reason: .lastMessageIsOwn))
}

/// Reading a room's photos gives them to the model as context; it does not make
/// a photo something to answer. Nothing here changes when a room turns photos
/// on — a picture still waits for someone to say something about it.
@Test
func photosAndEmoticonsAreNotAnswered() {
    let emoticon = engine.evaluate(
        request(
            room: directRoom,
            policy: policy(mode: .automatic),
            messages: [message(id: "m1", body: "", kind: .attachment)]
        )
    )
    let photo = engine.evaluate(
        request(
            room: directRoom,
            policy: policy(mode: .automatic),
            messages: [message(id: "m1", body: "사진", kind: .photo)]
        )
    )

    #expect(emoticon == .hold(reason: .nonTextMessage))
    #expect(photo == .hold(reason: .nonTextMessage))
}

@Test
func aRoomStaysQuietUntilItsMinimumIntervalHasPassed() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let outcome = engine.evaluate(
        request(
            room: directRoom,
            policy: policy(mode: .automatic, minimumInterval: 300),
            messages: [message(id: "m1", body: "또 물어봐도 돼?")],
            lastReplyAt: now.addingTimeInterval(-120),
            now: now
        )
    )

    #expect(outcome == .hold(reason: .cooldown(remaining: 180)))
}

@Test
func theRoomAnswersAgainOnceTheIntervalElapsed() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let outcome = engine.evaluate(
        request(
            room: directRoom,
            policy: policy(mode: .automatic, minimumInterval: 300),
            messages: [message(id: "m1", body: "또 물어봐도 돼?")],
            lastReplyAt: now.addingTimeInterval(-301),
            now: now
        )
    )

    #expect(outcome == .ask(trigger: .directQuestion, triggerMessageID: "m1"))
}

/// The hold arrives before a message is even looked at, so a room outside its
/// hours costs nothing: no model call, and no reason to read the conversation.
@Test
func aRoomOutsideItsActiveHoursHoldsBeforeAnythingElseIsChecked() {
    let outcome = engine.evaluate(
        request(
            room: directRoom,
            policy: policy(mode: .automatic, activeHours: workingHours),
            messages: [message(id: "m1", body: "자니?")],
            now: moment(23, 30),
            calendar: seoul
        )
    )

    #expect(outcome == .hold(reason: .outsideActiveHours))
}

@Test
func aRoomInsideItsActiveHoursAnswersAsUsual() {
    let outcome = engine.evaluate(
        request(
            room: directRoom,
            policy: policy(mode: .automatic, activeHours: workingHours),
            messages: [message(id: "m1", body: "내일 시간 돼?")],
            now: moment(13, 30),
            calendar: seoul
        )
    )

    #expect(outcome == .ask(trigger: .directQuestion, triggerMessageID: "m1"))
}

/// A night window is the one people actually set, and it is the one a naive
/// start-before-end check gets wrong.
@Test
func aWindowRunningPastMidnightStillAnswersInTheSmallHours() {
    let nightHours = ReplyActiveHours(isLimited: true, startMinute: 22 * 60, endMinute: 2 * 60)
    let atOne = engine.evaluate(
        request(
            room: directRoom,
            policy: policy(mode: .automatic, activeHours: nightHours),
            messages: [message(id: "m1", body: "아직 안 자?")],
            now: moment(1, 0),
            calendar: seoul
        )
    )
    let atNoon = engine.evaluate(
        request(
            room: directRoom,
            policy: policy(mode: .automatic, activeHours: nightHours),
            messages: [message(id: "m1", body: "점심 먹었어?")],
            now: moment(12, 0),
            calendar: seoul
        )
    )

    #expect(atOne == .ask(trigger: .directQuestion, triggerMessageID: "m1"))
    #expect(atNoon == .hold(reason: .outsideActiveHours))
}

@Test
func anEmptyRoomHasNothingToEvaluate() {
    let outcome = engine.evaluate(
        request(room: directRoom, policy: policy(mode: .automatic), messages: [])
    )

    #expect(outcome == .hold(reason: .noNewMessage))
}

// MARK: - Fixtures

private let workingHours = ReplyActiveHours(isLimited: true, startMinute: 9 * 60, endMinute: 18 * 60)

/// One fixed clock, so "23:30" means the same thing wherever the test runs.
private let seoul: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .gmt
    return calendar
}()

private func moment(_ hour: Int, _ minute: Int) -> Date {
    seoul.date(from: DateComponents(year: 2026, month: 3, day: 14, hour: hour, minute: minute))
        ?? Date(timeIntervalSince1970: 0)
}

private func policy(
    mode: ResponseMode,
    chance: InterjectionChance = .never,
    minimumInterval: TimeInterval = 300,
    judgementInterval: JudgementInterval = .immediate,
    activeHours: ReplyActiveHours = .always
) -> RoomPolicy {
    RoomPolicy(
        accountFingerprint: account,
        chatRoomID: "room",
        responseMode: mode,
        interjectionChance: chance,
        minimumInterval: minimumInterval,
        judgementInterval: judgementInterval,
        activeHours: activeHours
    )
}

private func message(
    id: String,
    senderID: String = "s1",
    body: String,
    kind: ChatMessage.Kind = .text,
    isFromMe: Bool = false,
    sentAt: Date = Date(timeIntervalSince1970: 1_000_000)
) -> ChatMessage {
    ChatMessage(
        id: id,
        chatRoomID: "room",
        sender: ChatMember(id: senderID, displayName: "상대"),
        body: body,
        sentAt: sentAt,
        kind: kind,
        isFromMe: isFromMe
    )
}

private func request(
    room: ChatRoom,
    policy: RoomPolicy,
    globalResponsesEnabled: Bool = true,
    accountVerified: Bool = true,
    messages: [ChatMessage] = [message(id: "m1", body: "안녕하세요")],
    lastReplyAt: Date? = nil,
    lastJudgementAt: Date? = nil,
    accountNickname: String? = nil,
    responseKeywords: [String] = ["한결"],
    now: Date = Date(timeIntervalSince1970: 1_000_000),
    calendar: Calendar = .current
) -> ReplyEvaluationRequest {
    ReplyEvaluationRequest(
        room: room,
        policy: policy,
        globalResponsesEnabled: globalResponsesEnabled,
        accountVerified: accountVerified,
        recentMessages: messages,
        lastReplyAt: lastReplyAt,
        lastJudgementAt: lastJudgementAt,
        accountNickname: accountNickname,
        responseKeywords: responseKeywords,
        now: now,
        calendar: calendar
    )
}
