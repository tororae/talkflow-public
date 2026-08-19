import Foundation
import Testing
@testable import TalkFlowDomain

private let account = "acct"
private let room = ChatRoom(id: "r1", displayName: "프로젝트 팀", kind: .group)
private let noon = Date(timeIntervalSince1970: 1_770_000_000)

private func policy(
    burning: BurningMode,
    chance: Int = 10,
    minimumInterval: TimeInterval = 300,
    judgement: JudgementInterval = JudgementInterval(fixed: 600)
) -> RoomPolicy {
    RoomPolicy(
        accountFingerprint: account,
        chatRoomID: room.id,
        responseMode: .automatic,
        interjectionChance: InterjectionChance(percent: chance),
        minimumInterval: minimumInterval,
        judgementInterval: judgement,
        burning: burning
    )
}

private func state(from start: Date = noon, lasting: TimeInterval, cooldown: TimeInterval) -> BurningState {
    BurningState(
        startedAt: start,
        endsAt: start.addingTimeInterval(lasting),
        cooldownUntil: start.addingTimeInterval(lasting + cooldown)
    )
}

/// Every room the app has is a constant: 10% of everything, every hour, forever.
/// A burn is the room behaving like somebody who sat down at it, and the three
/// numbers that decide pace are the three it swaps.
@Test
func aBurningRoomAnswersOnItsBurningNumbersInsteadOfItsOwn() {
    let mode = BurningMode(
        isEnabled: true,
        interjectionChance: InterjectionChance(percent: 90),
        minimumInterval: 0,
        judgementInterval: .immediate
    )
    let burning = policy(burning: mode)
        .whileBurning(state(lasting: 600, cooldown: 3_600), at: noon.addingTimeInterval(60))

    #expect(burning.interjectionChance.percent == 90)
    #expect(burning.minimumInterval == 0)
    #expect(burning.judgementInterval == .immediate)
}

/// What it says is not what changes. Only the pace is swapped, so a room keeps
/// its own condition and its own voice through a burn.
@Test
func aBurnChangesThePaceAndNothingAboutTheAnswer() {
    let mode = BurningMode(isEnabled: true)
    var base = policy(burning: mode)
    base.answeringConditionOverride = AnsweringCondition("일정 얘기만")
    base.responseStyleOverride = ResponseStyle(tone: "정중하게")

    let burning = base.whileBurning(state(lasting: 600, cooldown: 3_600), at: noon.addingTimeInterval(60))

    #expect(burning.answeringConditionOverride == base.answeringConditionOverride)
    #expect(burning.responseStyleOverride == base.responseStyleOverride)
    #expect(burning.responseMode == base.responseMode)
}

@Test
func aRoomPastTheEndOfItsBurnIsBackOnItsOwnNumbers() {
    let mode = BurningMode(isEnabled: true, interjectionChance: InterjectionChance(percent: 90))
    let after = policy(burning: mode)
        .whileBurning(state(lasting: 600, cooldown: 3_600), at: noon.addingTimeInterval(601))

    #expect(after.interjectionChance.percent == 10)
    #expect(after.minimumInterval == 300)
}

/// The switch is the consent. A room holding burning numbers it never turned on
/// must answer exactly as it reads on screen.
@Test
func aRoomWithBurningOffIsUntouchedByAStateItSomehowHas() {
    let mode = BurningMode(isEnabled: false, interjectionChance: InterjectionChance(percent: 90))
    let untouched = policy(burning: mode)
        .whileBurning(state(lasting: 600, cooldown: 3_600), at: noon.addingTimeInterval(60))

    #expect(untouched.interjectionChance.percent == 10)
}

/// Asked after answering rather than before: a burn is a room that got a reply
/// out of somebody, and starting one on a message nobody answered would put the
/// app in a hurry to say nothing.
@Test
func ananswerCanStartABurnWhenTheDrawLandsInside() {
    let mode = BurningMode(isEnabled: true, chance: InterjectionChance(percent: 10))

    #expect(policy(burning: mode).startsBurning(after: nil, at: noon, roll: .always))
    #expect(!policy(burning: mode).startsBurning(after: nil, at: noon, roll: .never))
}

/// A person who was just on the chat for twenty minutes is not back twenty
/// minutes later, so the cooldown holds even on a draw that would have hit.
@Test
func aRoomInsideItsCooldownCannotStartAnotherBurn() {
    let mode = BurningMode(isEnabled: true, chance: InterjectionChance(percent: 100))
    let previous = state(lasting: 600, cooldown: 3_600)

    #expect(!policy(burning: mode).startsBurning(after: previous, at: noon.addingTimeInterval(700), roll: .always))
    #expect(policy(burning: mode).startsBurning(after: previous, at: noon.addingTimeInterval(4_201), roll: .always))
}

@Test
func aRoomWithBurningOffNeverStartsOneHoweverTheDrawLands() {
    let mode = BurningMode(isEnabled: false, chance: InterjectionChance(percent: 100))

    #expect(!policy(burning: mode).startsBurning(after: nil, at: noon, roll: .always))
}

/// The cooldown outlasts the burn, and in between the room is neither burning
/// nor free to start again. Three states, so the screen can say which.
@Test
func aBurnIsFollowedByACooldownThatIsNotItself() {
    let window = state(lasting: 600, cooldown: 3_600)

    #expect(window.isBurning(at: noon.addingTimeInterval(1)))
    #expect(!window.isCoolingDown(at: noon.addingTimeInterval(1)))

    #expect(!window.isBurning(at: noon.addingTimeInterval(601)))
    #expect(window.isCoolingDown(at: noon.addingTimeInterval(601)))

    #expect(!window.isBurning(at: noon.addingTimeInterval(4_201)))
    #expect(!window.isCoolingDown(at: noon.addingTimeInterval(4_201)))
}

/// Nothing in this app runs on a clock, so a burn that ended while nobody was
/// looking has to still be owed its last word when the room is next examined.
@Test
func aBurnThatEndedUnwatchedIsStillOwedItsLastWord() {
    let window = state(lasting: 600, cooldown: 3_600)
    let afterEnd = noon.addingTimeInterval(9_000)

    #expect(window.hasJustEnded(at: afterEnd, announcedAt: nil))
    #expect(!window.hasJustEnded(at: noon.addingTimeInterval(599), announcedAt: nil))
}

/// And said once. The room is looked at on every sync, and a burn that announced
/// its own end is not owed a second one.
@Test
func aBurnThatAlreadySaidGoodbyeDoesNotSayItAgain() {
    let window = state(lasting: 600, cooldown: 3_600)

    #expect(!window.hasJustEnded(at: noon.addingTimeInterval(900), announcedAt: noon.addingTimeInterval(605)))
}

/// A range that varies the wait is worth having; one that varies a probability
/// is not. Drawing p from a range and rolling against it fires as often as
/// rolling against the middle, so the setting is a single number and the doc
/// says why. This pins the shape so a future range cannot arrive unnoticed.
@Test
func theTriggerChanceIsOneNumberAndTheDurationsAreRanges() {
    let mode = BurningMode.off

    #expect(mode.chance.percent == 10)
    #expect(!mode.duration.isFixed)
    #expect(!mode.cooldown.isFixed)
}

@Test
func everyRoomStartsWithBurningOff() {
    let fresh = RoomPolicy.makeDefault(accountFingerprint: account, room: room)

    #expect(fresh.burning.isEnabled == false)
}

/// The gate that keeps this from being a bot posting 「왔다」 into an empty room
/// every morning. A line about somebody arriving or leaving is worth something
/// only while there is a conversation for it to land in.
@Test
func anAnnouncementNeedsAConversationRecentEnoughToLandIn() {
    let announcements = StateAnnouncements(
        transitions: [.burningEnded],
        withinRecentConversation: 600
    )

    #expect(announcements.worthTelling(lastMessageAt: noon.addingTimeInterval(-60), at: noon))
    #expect(!announcements.worthTelling(lastMessageAt: noon.addingTimeInterval(-3_600), at: noon))
    #expect(!announcements.worthTelling(lastMessageAt: nil, at: noon))
}

/// Every room starts silent, like 먼저 말 걸기 and for the same reason: this is the
/// app speaking without being spoken to, and nothing may turn that on by
/// implication — not 집중 시간, not 자동응답.
@Test
func everyRoomStartsAnnouncingNothing() {
    let fresh = RoomPolicy.makeDefault(accountFingerprint: account, room: room)

    #expect(fresh.announcements.isOn == false)
    #expect(fresh.announcements.transitions.isEmpty)
}

/// Turning a burn on is not turning speaking on. The two switches are separate
/// because the permissions are.
@Test
func aBurningRoomStillAnnouncesNothingUntilAskedTo() {
    var policy = RoomPolicy.makeDefault(accountFingerprint: account, room: room)
    policy.burning = BurningMode(isEnabled: true)

    #expect(!policy.announcements.announces(.burningStarted))
    #expect(!policy.announcements.announces(.burningEnded))
}

/// Ordered by when they last came up, so nobody has to rank a person's addresses
/// by hand. A link nobody has mentioned in months falls off the end of a prompt
/// on its own, and one never seen sorts last rather than first.
@Test
func aReplyCarriesTheLinksThatCameUpMostRecently() {
    let note = PersonNote(
        chatRoomID: "room-1",
        senderID: "s1",
        displayName: "민준아빠",
        note: "앱을 만들었다고 함.",
        links: (1...7).map {
            PersonLink(
                label: "링크\($0)",
                url: "https://example.com/\($0)",
                lastMentionedAt: $0 == 7 ? nil : noon.addingTimeInterval(TimeInterval($0))
            )
        },
        updatedAt: noon
    )

    #expect(note.links.count == 7)
    #expect(note.linksForReply.count == PersonNote.linksPerReply)
    #expect(note.linksForReply.first?.label == "링크6")
    #expect(!note.linksForReply.contains { $0.label == "링크7" })
}

/// Whose work it is, and the honest answer for most links. A model asked to
/// choose between made and shared will choose, and 「형이 만든 그 앱」 about a
/// forwarded link credits somebody with a stranger's work.
@Test
func aLinkNobodyClaimedIsRecordedAsUnknownRatherThanGuessed() {
    let link = PersonLink(label: "블로그", url: "https://example.com")

    #expect(link.relation == .unknown)
    #expect(link.relation.title == "모름")
}
