import Foundation
import Testing
@testable import TalkFlowDomain

private let account = "katok-opener"
private let room = ChatRoom(id: "room-g", displayName: "프로젝트 팀", kind: .group)
private let now = Date(timeIntervalSince1970: 1_700_000_000)
private let gate = ConversationOpenerGate()

/// The whole premise of this feature: it is off, everywhere, until somebody goes
/// and turns it on for one room. Not switched on by enabling the room, not by
/// 자동응답, not by 상시 전송.
@Test
func aRoomTalkFlowHasNeverBeenToldAboutDoesNotSpeakFirst() {
    let fresh = RoomPolicy.makeDefault(accountFingerprint: account, room: room)
    var enabled = fresh
    enabled.responseMode = RoomPolicy.initialEnabledMode(for: room)
    enabled.deliveryMode = .always

    #expect(fresh.conversationOpener == .off)
    #expect(enabled.conversationOpener == .off)
    #expect(enabled.openerDeliversAutomatically == false)
}

@Test
func aQuietRoomThatHasWaitedItsTurnIsOpened() {
    #expect(gate.evaluate(request()) == .open)
}

/// Each of these on its own. A gate that only holds because another one happens
/// to be holding too is a gate that disappears the day the other one moves.
@Test
func theGlobalSwitchAloneKeepsTheRoomSilent() {
    #expect(gate.evaluate(request(globalEnabled: false)) == .hold(reason: .globalPause))
}

@Test
func anUnverifiedAccountAloneKeepsTheRoomSilent() {
    #expect(gate.evaluate(request(accountVerified: false)) == .hold(reason: .accountUnverified))
}

@Test
func theSettingBeingOffAloneKeepsTheRoomSilent() {
    #expect(gate.evaluate(request(opener: .off)) == .hold(reason: .switchedOff))
}

/// A room the user switched off must not start talking, whatever else it says.
@Test
func aRoomSwitchedOffOrLeftDetectingOnlyNeverSpeaksFirst() {
    #expect(gate.evaluate(request(mode: .off)) == .hold(reason: .roomDisabled))
    #expect(gate.evaluate(request(mode: .detectOnly)) == .hold(reason: .roomDisabled))
}

/// 멘션에만 응답 is deliberately not on that list: it says which messages get
/// answered, and requiring 자동응답 would make one switch quietly change what the
/// room does about everybody else's messages.
@Test
func aMentionOnlyRoomMayStillBeOpened() {
    #expect(gate.evaluate(request(mode: .mentionOnly)) == .open)
}

/// An unprompted message at four in the morning is the clearest possible way for
/// this feature to be wrong.
@Test
func theRoomsAnsweringHoursApplyToSpeakingFirstAsWell() {
    let outcome = gate.evaluate(
        request(activeHours: ReplyActiveHours(isLimited: true, startMinute: 9 * 60, endMinute: 18 * 60))
    )

    #expect(outcome == .hold(reason: .outsideActiveHours))
}

/// Opening a subject while people are mid-conversation is not starting a
/// conversation, it is interrupting one.
@Test
func aRoomThatIsStillTalkingIsNotOpened() {
    let outcome = gate.evaluate(request(lastMessageAgo: 600))

    #expect(outcome == .hold(reason: .stillTalking(quietFor: 600)))
}

/// An opener nobody answered leaves TalkFlow holding the last word. Speaking
/// again there is a bot talking to itself, which is the failure this feature
/// produces most easily.
@Test
func aRoomWhereTalkFlowSpokeLastIsNotOpenedAgain() {
    let outcome = gate.evaluate(
        request(
            messages: [
                message(id: "m1", body: "그럼 그렇게 하죠", at: now.addingTimeInterval(-7200), isFromMe: true)
            ]
        )
    )

    #expect(outcome == .hold(reason: .spokeLast))
}

/// The subject has to come out of this room's own conversation, so a room with no
/// conversation has nothing to open.
@Test
func aRoomWithNothingInItIsNotOpened() {
    #expect(gate.evaluate(request(messages: [])) == .hold(reason: .noConversation))
}

@Test
func aRoomStillInsideItsSilenceWindowIsHeldUntilItPasses() {
    // Quiet for 40 minutes, but this room's opener wait is a fixed hour, so it is
    // not due. The wait is the silence itself now, measured from the last message
    // rather than a cycle off the last model call.
    let outcome = gate.evaluate(
        request(interval: JudgementInterval(fixed: 3600), lastMessageAgo: 2400)
    )

    #expect(outcome == .hold(reason: .stillTalking(quietFor: 2400)))
}

/// 답변 활성화 시간 is open but 먼저 말 걸기's own hours are not: the narrower window
/// wins, so speaking first is held even where a reply would go out.
@Test
func aRoomInsideAnsweringHoursButOutsideOpenerHoursIsHeld() {
    let outcome = gate.evaluate(
        request(openerHours: ReplyActiveHours(isLimited: true, startMinute: 9 * 60, endMinute: 18 * 60))
    )

    #expect(outcome == .hold(reason: .outsideOpenerHours))
}

/// TalkFlow spoke last, but this room may open again without an answer and has not
/// used up its run — so it opens rather than falling to spokeLast.
@Test
func aRoomThatAllowsRepeatsOpensAgainEvenThoughTalkFlowSpokeLast() {
    let outcome = gate.evaluate(
        request(
            repeatLimit: 3,
            opensSinceTheyLastSpoke: 1,
            messages: [
                message(id: "m1", body: "그럼 그렇게 하죠", at: now.addingTimeInterval(-7200), isFromMe: true)
            ]
        )
    )

    #expect(outcome == .open)
}

/// The same room once it has opened its whole run with no answer: it stops rather
/// than talking to itself forever.
@Test
func aRoomThatHasUsedUpItsRepeatRunStops() {
    let outcome = gate.evaluate(
        request(
            repeatLimit: 3,
            opensSinceTheyLastSpoke: 3,
            messages: [
                message(id: "m1", body: "그럼 그렇게 하죠", at: now.addingTimeInterval(-7200), isFromMe: true)
            ]
        )
    )

    #expect(outcome == .hold(reason: .repeatLimitReached))
}

/// ④ 비활성 주기 정지: with the pause on, only the seconds inside 먼저 말 걸기's own
/// hours run the silence clock down. A full day has passed on the wall clock, but
/// the room's window is 20:00–23:00 — three hours a day — so a day-old silence has
/// accrued only three hours of wait, short of the four this room asks for, and it
/// is held.
@Test
func withThePauseOnOnlyTheHoursInsideTheWindowCountTowardTheWait() {
    let hours = ReplyActiveHours(isLimited: true, startMinute: 20 * 60, endMinute: 23 * 60)
    let outcome = gate.evaluate(
        request(
            openerHours: hours,
            interval: JudgementInterval(fixed: 4 * 3600),
            pausesOutsideHours: true,
            lastMessageAgo: 24 * 3600
        )
    )

    #expect(outcome == .hold(reason: .stillTalking(quietFor: 3 * 3600)))
}

/// The same room, the same day-old silence, but the pause off: the clock runs
/// straight through the closed hours, the wall-clock gap is a whole day, and four
/// hours passed long ago — so it opens. The one flag is the whole difference.
@Test
func withThePauseOffTheClockRunsStraightThroughTheClosedHours() {
    let hours = ReplyActiveHours(isLimited: true, startMinute: 20 * 60, endMinute: 23 * 60)
    let outcome = gate.evaluate(
        request(
            openerHours: hours,
            interval: JudgementInterval(fixed: 4 * 3600),
            pausesOutsideHours: false,
            lastMessageAgo: 24 * 3600
        )
    )

    #expect(outcome == .open)
}

// MARK: - Fixtures

private func message(id: String, body: String, at sentAt: Date, isFromMe: Bool = false) -> ChatMessage {
    ChatMessage(
        id: id,
        chatRoomID: room.id,
        sender: ChatMember(id: "s1", displayName: "지수"),
        body: body,
        sentAt: sentAt,
        isFromMe: isFromMe
    )
}

/// A room two hours quiet, an hour of interval behind it, and every other gate
/// open — so each test can close exactly one and see it close.
private func request(
    opener: ConversationOpener = .draftOnly,
    mode: ResponseMode = .automatic,
    globalEnabled: Bool = true,
    accountVerified: Bool = true,
    activeHours: ReplyActiveHours = .always,
    openerHours: ReplyActiveHours = .always,
    interval: JudgementInterval = JudgementInterval(fixed: 3600),
    repeatLimit: Int = 0,
    opensSinceTheyLastSpoke: Int = 0,
    pausesOutsideHours: Bool = false,
    lastMessageAgo: TimeInterval = 7200,
    messages: [ChatMessage]? = nil,
    at moment: Date = now
) -> ConversationOpenerRequest {
    var policy = RoomPolicy.makeDefault(accountFingerprint: account, room: room)
    policy.responseMode = mode
    policy.activeHours = activeHours
    policy.conversationOpenerHours = openerHours
    policy.conversationOpener = opener
    policy.conversationOpenerInterval = interval
    policy.openerRepeatLimit = repeatLimit
    policy.openerCadencePausesOutsideHours = pausesOutsideHours

    return ConversationOpenerRequest(
        room: room,
        policy: policy,
        globalResponsesEnabled: globalEnabled,
        accountVerified: accountVerified,
        recentMessages: messages ?? [
            message(id: "m1", body: "그거 다음 주에 하기로 했었죠", at: moment.addingTimeInterval(-lastMessageAgo))
        ],
        opensSinceTheyLastSpoke: opensSinceTheyLastSpoke,
        now: moment,
        calendar: gmt,
        roll: JudgementRoll.fromCycleStart
    )
}

/// The hours are read on a wall clock, so the tests pin one rather than depending
/// on where the machine is. `now` is 22:13 in this calendar, which is outside the
/// 09:00–18:00 window the hours test sets and inside every unlimited one.
private let gmt: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    return calendar
}()
