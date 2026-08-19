import Foundation
import GRDB
import Testing
import TalkFlowDomain
@testable import TalkFlowInfrastructure

/// Two whole policies and a field-by-field comparison, for pinning what the
/// policy row actually stores.
///
/// `save` used to keep the same 48 column names in four hand-maintained lists —
/// the INSERT columns, the `DO UPDATE SET` list, 48 positional placeholders and
/// the arguments array — with a fifth in the row reader, where two of them in a
/// different order compiled and swapped two values. `RoomPolicyRow.CodingKeys` is
/// the one list now, but the fixture's job has not changed: a swap anywhere
/// between a setting and its column has to be impossible to miss, so every
/// boolean alternates rather than all being true, and no two numbers in one policy
/// share a value.

let persistedAccount = "katok-persistence"
let persistedOtherAccount = "katok-persistence-other"
let persistedRoom = ChatRoom(id: "room-persist-1", displayName: "정책 방", kind: .group)
let persistedOtherRoom = ChatRoom(id: "room-persist-2", displayName: "다른 방", kind: .direct)

func makePolicyDatabase() throws -> (TalkFlowDatabase, () -> Void) {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "talkflow-policy-\(UUID().uuidString)/talkflow.sqlite")
    let database = try TalkFlowDatabase(fileURL: url)
    return (database, { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) })
}

/// Every mutable field away from its default, every number distinct, every
/// boolean the opposite of the one before it.
func policySetOneWay(room: String, account: String = persistedAccount) -> RoomPolicy {
    RoomPolicy(
        accountFingerprint: account,
        chatRoomID: room,
        responseMode: .detectOnly,
        interjectionChance: InterjectionChance(percent: 37),
        deliveryMode: .autoSendWhenIdle,
        minimumInterval: 111,
        judgementInterval: JudgementInterval(measure: .messages, shortest: 7, longest: 19),
        activeHours: ReplyActiveHours(isLimited: false, startMinute: 61, endMinute: 1_319),
        readsPhotos: true,
        webSearch: false,
        readsLinks: true,
        conversationOpener: .draftOnly,
        conversationOpenerInterval: JudgementInterval(shortest: 2_222, longest: 3_333),
        conversationOpenerHours: ReplyActiveHours(isLimited: true, startMinute: 137, endMinute: 941),
        openerRepeatLimit: 3,
        openerRepeatTopic: .fresh,
        openerCadencePausesOutsideHours: false,
        openerPromptHint: "요즘 하는 프로젝트 얘기 꺼내",
        responseKeywords: ["코드명", "dalbit-1"],
        answeringConditionOverride: AnsweringCondition("이 방은 급한 것만"),
        responseStyleOverride: ResponseStyle(
            tone: "짧고 무뚝뚝하게",
            length: .long,
            emojiUse: .frequent,
            assertiveness: .forward
        ),
        remembersConversation: true,
        answersReplies: false,
        burning: BurningMode(
            isEnabled: false,
            chance: InterjectionChance(percent: 41),
            duration: JudgementInterval(shortest: 4_444, longest: 5_555),
            cooldown: JudgementInterval(shortest: 6_666, longest: 7_777),
            interjectionChance: InterjectionChance(percent: 53),
            minimumInterval: 888,
            judgementInterval: JudgementInterval(shortest: 99, longest: 1_001)
        ),
        announcements: StateAnnouncements(
            transitions: [.burningStarted, .activeHoursClosed],
            withinRecentConversation: 1_234,
            delivery: .delivers
        ),
        remembersPeople: true
    )
}

/// The same fields again, with every boolean inverted and every number changed.
/// Saved over the one above it proves the `DO UPDATE SET` list carries all 46
/// non-key columns, which the first save cannot show.
func policySetTheOtherWay(room: String, account: String = persistedAccount) -> RoomPolicy {
    RoomPolicy(
        accountFingerprint: account,
        chatRoomID: room,
        responseMode: .automatic,
        interjectionChance: InterjectionChance(percent: 62),
        deliveryMode: .always,
        minimumInterval: 222,
        judgementInterval: JudgementInterval(measure: .seconds, shortest: 45, longest: 315),
        activeHours: ReplyActiveHours(isLimited: true, startMinute: 480, endMinute: 1_200),
        readsPhotos: false,
        webSearch: true,
        readsLinks: false,
        conversationOpener: .delivers,
        conversationOpenerInterval: JudgementInterval(shortest: 5_400, longest: 9_900),
        conversationOpenerHours: ReplyActiveHours(isLimited: false, startMinute: 75, endMinute: 1_020),
        openerRepeatLimit: 6,
        openerRepeatTopic: .carryOn,
        openerCadencePausesOutsideHours: true,
        openerPromptHint: "새 프로젝트 얘기로 넘어가",
        responseKeywords: ["다른-코드명"],
        answeringConditionOverride: AnsweringCondition("여기서는 일정 얘기만"),
        responseStyleOverride: ResponseStyle(
            tone: "정중하고 길게",
            length: .medium,
            emojiUse: .none,
            assertiveness: .balanced
        ),
        remembersConversation: false,
        answersReplies: true,
        burning: BurningMode(
            isEnabled: true,
            chance: InterjectionChance(percent: 71),
            duration: JudgementInterval(shortest: 1_800, longest: 2_700),
            cooldown: JudgementInterval(shortest: 3_600, longest: 8_100),
            interjectionChance: InterjectionChance(percent: 29),
            minimumInterval: 660,
            judgementInterval: JudgementInterval(shortest: 30, longest: 150)
        ),
        announcements: StateAnnouncements(
            transitions: [.burningEnded, .activeHoursOpened, .activeHoursClosed],
            withinRecentConversation: 2_400,
            delivery: .draftOnly
        ),
        remembersPeople: false
    )
}

/// One assertion per stored column, each naming the field it is about.
///
/// `read == written` on the whole struct would say "different" and leave the
/// reader to diff 48 values by eye; the point of the net is to name the column
/// that broke.
func expectEveryField(
    _ read: RoomPolicy,
    matches expected: RoomPolicy,
    _ label: String
) {
    func check<Value: Equatable>(_ field: String, _ lhs: Value, _ rhs: Value) {
        #expect(lhs == rhs, "\(label) — \(field): 저장 \(rhs), 읽기 \(lhs)")
    }

    check("accountFingerprint", read.accountFingerprint, expected.accountFingerprint)
    check("chatRoomID", read.chatRoomID, expected.chatRoomID)
    check("responseMode", read.responseMode, expected.responseMode)
    check("interjectionChance", read.interjectionChance.percent, expected.interjectionChance.percent)
    check("deliveryMode", read.deliveryMode, expected.deliveryMode)
    check("minimumInterval", read.minimumInterval, expected.minimumInterval)
    check("judgementInterval.measure", read.judgementInterval.measure, expected.judgementInterval.measure)
    check("judgementInterval.shortest", read.judgementInterval.shortest, expected.judgementInterval.shortest)
    check("judgementInterval.longest", read.judgementInterval.longest, expected.judgementInterval.longest)
    check("activeHours.isLimited", read.activeHours.isLimited, expected.activeHours.isLimited)
    check("activeHours.startMinute", read.activeHours.startMinute, expected.activeHours.startMinute)
    check("activeHours.endMinute", read.activeHours.endMinute, expected.activeHours.endMinute)
    check("readsPhotos", read.readsPhotos, expected.readsPhotos)
    check("webSearch", read.webSearch, expected.webSearch)
    check("readsLinks", read.readsLinks, expected.readsLinks)
    check("conversationOpener", read.conversationOpener, expected.conversationOpener)
    check(
        "conversationOpenerInterval.shortest",
        read.conversationOpenerInterval.shortest,
        expected.conversationOpenerInterval.shortest
    )
    check(
        "conversationOpenerInterval.longest",
        read.conversationOpenerInterval.longest,
        expected.conversationOpenerInterval.longest
    )
    check(
        "conversationOpenerHours.isLimited",
        read.conversationOpenerHours.isLimited,
        expected.conversationOpenerHours.isLimited
    )
    check(
        "conversationOpenerHours.startMinute",
        read.conversationOpenerHours.startMinute,
        expected.conversationOpenerHours.startMinute
    )
    check(
        "conversationOpenerHours.endMinute",
        read.conversationOpenerHours.endMinute,
        expected.conversationOpenerHours.endMinute
    )
    check("openerRepeatLimit", read.openerRepeatLimit, expected.openerRepeatLimit)
    check("openerRepeatTopic", read.openerRepeatTopic, expected.openerRepeatTopic)
    check(
        "openerCadencePausesOutsideHours",
        read.openerCadencePausesOutsideHours,
        expected.openerCadencePausesOutsideHours
    )
    check("openerPromptHint", read.openerPromptHint, expected.openerPromptHint)
    check("responseKeywords", read.responseKeywords, expected.responseKeywords)
    check(
        "answeringConditionOverride",
        read.answeringConditionOverride?.text,
        expected.answeringConditionOverride?.text
    )
    check("usesOwnResponseStyle", read.usesOwnResponseStyle, expected.usesOwnResponseStyle)
    check("responseStyleOverride.tone", read.responseStyleOverride?.tone, expected.responseStyleOverride?.tone)
    check("responseStyleOverride.length", read.responseStyleOverride?.length, expected.responseStyleOverride?.length)
    check(
        "responseStyleOverride.emojiUse",
        read.responseStyleOverride?.emojiUse,
        expected.responseStyleOverride?.emojiUse
    )
    check(
        "responseStyleOverride.assertiveness",
        read.responseStyleOverride?.assertiveness,
        expected.responseStyleOverride?.assertiveness
    )
    check("remembersConversation", read.remembersConversation, expected.remembersConversation)
    check("answersReplies", read.answersReplies, expected.answersReplies)
    check("burning.isEnabled", read.burning.isEnabled, expected.burning.isEnabled)
    check("burning.chance", read.burning.chance.percent, expected.burning.chance.percent)
    check("burning.duration.shortest", read.burning.duration.shortest, expected.burning.duration.shortest)
    check("burning.duration.longest", read.burning.duration.longest, expected.burning.duration.longest)
    check("burning.cooldown.shortest", read.burning.cooldown.shortest, expected.burning.cooldown.shortest)
    check("burning.cooldown.longest", read.burning.cooldown.longest, expected.burning.cooldown.longest)
    check(
        "burning.interjectionChance",
        read.burning.interjectionChance.percent,
        expected.burning.interjectionChance.percent
    )
    check("burning.minimumInterval", read.burning.minimumInterval, expected.burning.minimumInterval)
    check(
        "burning.judgementInterval.shortest",
        read.burning.judgementInterval.shortest,
        expected.burning.judgementInterval.shortest
    )
    check(
        "burning.judgementInterval.longest",
        read.burning.judgementInterval.longest,
        expected.burning.judgementInterval.longest
    )
    check("announcements.transitions", read.announcements.transitions, expected.announcements.transitions)
    check(
        "announcements.withinRecentConversation",
        read.announcements.withinRecentConversation,
        expected.announcements.withinRecentConversation
    )
    check("announcements.delivery", read.announcements.delivery, expected.announcements.delivery)
    check("remembersPeople", read.remembersPeople, expected.remembersPeople)
}
