import Foundation
import GRDB
import TalkFlowDomain

/// The two directions between a room's settings and its row.
///
/// Kept apart from `RoomPolicyRow` because they are different jobs: that file
/// says which columns exist, this one says what their values mean. Everything
/// that used to be spread across `save`'s arguments array and the row reader is
/// here, once each way.
extension RoomPolicyRow {
    init(policy: RoomPolicy) {
        let style = policy.responseStyleOverride ?? ResponseStyle()
        accountFingerprint = policy.accountFingerprint
        chatRoomID = policy.chatRoomID
        responseMode = policy.responseMode.rawValue
        interjectionChance = policy.interjectionChance.percent
        deliveryMode = policy.deliveryMode.rawValue
        minimumInterval = policy.minimumInterval
        judgementInterval = policy.judgementInterval.shortest
        judgementIntervalLongest = policy.judgementInterval.longest
        judgementIntervalUnit = policy.judgementInterval.measure.rawValue
        activeHoursLimited = policy.activeHours.isLimited
        activeHoursStartMinute = policy.activeHours.startMinute
        activeHoursEndMinute = policy.activeHours.endMinute
        readsPhotos = policy.readsPhotos
        webSearch = policy.webSearch
        readsLinks = policy.readsLinks
        conversationOpener = policy.conversationOpener.rawValue
        // 집중 시간's cycle and 먼저 말 걸기's cadence have no unit column, so both
        // store their two numbers and read back as seconds. Pinned by a test, not
        // an oversight to correct in passing.
        conversationOpenerShortest = policy.conversationOpenerInterval.shortest
        conversationOpenerLongest = policy.conversationOpenerInterval.longest
        responseKeywords = KeywordColumn.encode(policy.responseKeywords)
        answeringCondition = policy.answeringConditionOverride?.text
        usesOwnStyle = policy.usesOwnResponseStyle
        // Written even when the room follows the global, so the columns always
        // hold a style the reader can build. Which of the two is in force is
        // `uses_own_style`, and only that.
        styleTone = style.tone
        styleLength = style.length.rawValue
        styleEmojiUse = style.emojiUse.rawValue
        styleAssertiveness = style.assertiveness.rawValue
        remembersConversation = policy.remembersConversation
        answersReplies = policy.answersReplies
        burningEnabled = policy.burning.isEnabled
        burningChance = policy.burning.chance.percent
        burningDurationShortest = policy.burning.duration.shortest
        burningDurationLongest = policy.burning.duration.longest
        burningCooldownShortest = policy.burning.cooldown.shortest
        burningCooldownLongest = policy.burning.cooldown.longest
        burningInterjectionChance = policy.burning.interjectionChance.percent
        burningMinimumInterval = policy.burning.minimumInterval
        burningJudgementInterval = policy.burning.judgementInterval.shortest
        burningJudgementIntervalLongest = policy.burning.judgementInterval.longest
        // Sorted, which is what makes the stored text stable: the domain holds a
        // set, and a set's iteration order would rewrite this column with the
        // same transitions in a new arrangement on every save.
        announcementTransitions = KeywordColumn
            .encode(policy.announcements.transitions.map(\.rawValue).sorted())
        announcementRecentWindow = policy.announcements.withinRecentConversation
        announcementDelivery = policy.announcements.delivery.rawValue
        remembersPeople = policy.remembersPeople
        openerHoursLimited = policy.conversationOpenerHours.isLimited
        openerHoursStartMinute = policy.conversationOpenerHours.startMinute
        openerHoursEndMinute = policy.conversationOpenerHours.endMinute
        openerRepeatLimit = policy.openerRepeatLimit
        openerRepeatTopic = policy.openerRepeatTopic.rawValue
        openerCadencePausesOutsideHours = policy.openerCadencePausesOutsideHours
        openerPromptHint = policy.openerPromptHint
    }
}

extension RoomPolicy {
    /// A stored row read as a policy, or nil for a row this build cannot make
    /// sense of — which the caller treats as "no policy" and answers with the
    /// room's default rather than an error.
    ///
    /// Only 응답 방식 and 전송 방식 can do that, because they are the two values
    /// with no honest fallback: a mode nobody recognises might be off and might be
    /// 자동응답, and guessing either way is either a silenced room or a room
    /// answering when it was told not to. Every other unrecognised word takes a
    /// named default below.
    ///
    /// No fallback for a *missing* value, unlike the reader this replaces. Every
    /// column but `answering_condition` (v12) and `opener_prompt_hint` (v29) is
    /// `NOT NULL`, and every one added after v1 arrived `.defaults(to:)`, which
    /// SQLite writes into the rows already on disk: v4 hours and tagging, v5
    /// photos, v6 keywords, v7 and v9 the judgement interval, v11 openers, v12 the
    /// chance and the style columns, v13 the interval's unit, v14 room memory, v16
    /// 답장 응답, v18 the ten 집중 시간 columns, v20 상태 알림, v22 사람 기억, v27 웹
    /// 검색, v28 링크 읽기, v29 six of the seven opener columns — the seventh is
    /// `opener_prompt_hint`, which is the nullable one. `minimum_interval`,
    /// `response_mode` and `delivery_mode` are from v1 and `NOT NULL` with no
    /// default, which is the same guarantee by a different route: a row cannot
    /// exist without them. So the old `?? 300`, `?? false`, `?? true` and friends
    /// could only have fired on a row that violated its own constraint.
    init?(row: RoomPolicyRow) {
        guard let mode = ResponseMode(rawValue: row.responseMode),
              let delivery = DeliveryMode(rawValue: row.deliveryMode)
        else {
            return nil
        }

        self.init(
            accountFingerprint: row.accountFingerprint,
            chatRoomID: row.chatRoomID,
            responseMode: mode,
            interjectionChance: InterjectionChance(percent: row.interjectionChance),
            deliveryMode: delivery,
            minimumInterval: row.minimumInterval,
            // A room stored before the interval had a top end reads back as a
            // fixed one: `JudgementInterval` raises a zero top to whatever the
            // bottom is, so the wait it kept before the upgrade is the wait it
            // keeps after. A unit nobody recognises reads as seconds — that is
            // what every number in this column meant before the count existed,
            // and guessing 개 would silently turn a five-minute cycle into a
            // five-message one.
            judgementInterval: JudgementInterval(
                measure: JudgementInterval.Measure(rawValue: row.judgementIntervalUnit) ?? .seconds,
                shortest: row.judgementInterval,
                longest: row.judgementIntervalLongest
            ),
            activeHours: ReplyActiveHours(
                isLimited: row.activeHoursLimited,
                startMinute: row.activeHoursStartMinute,
                endMinute: row.activeHoursEndMinute
            ),
            readsPhotos: row.readsPhotos,
            webSearch: row.webSearch,
            readsLinks: row.readsLinks,
            // A value nobody recognises reads back with openers off. There is no
            // reading of an unknown word that justifies speaking unasked.
            conversationOpener: ConversationOpener(rawValue: row.conversationOpener) ?? .off,
            conversationOpenerInterval: JudgementInterval(
                shortest: row.conversationOpenerShortest,
                longest: row.conversationOpenerLongest
            ),
            conversationOpenerHours: ReplyActiveHours(
                isLimited: row.openerHoursLimited,
                startMinute: row.openerHoursStartMinute,
                endMinute: row.openerHoursEndMinute
            ),
            openerRepeatLimit: row.openerRepeatLimit,
            // 이어가기 for a word nobody recognises, which is how every room
            // behaved before v29 gave the opener a topic to choose.
            openerRepeatTopic: OpenerRepeatTopic(rawValue: row.openerRepeatTopic) ?? .carryOn,
            openerCadencePausesOutsideHours: row.openerCadencePausesOutsideHours,
            openerPromptHint: row.openerPromptHint,
            responseKeywords: KeywordColumn.decode(row.responseKeywords),
            // Null is "follow 설정", which every room configured before this
            // existed holds. An empty string is not null: it is a room told to
            // judge with no condition at all.
            answeringConditionOverride: row.answeringCondition.map(AnsweringCondition.init),
            responseStyleOverride: Self.styleOverride(in: row),
            remembersConversation: row.remembersConversation,
            answersReplies: row.answersReplies,
            burning: Self.burning(in: row),
            announcements: Self.announcements(in: row),
            remembersPeople: row.remembersPeople
        )
    }

    /// A room's 상태 알림.
    ///
    /// The transitions are stored the way keywords are — raw values joined with a
    /// comma — and anything the enum does not recognise is dropped rather than
    /// refused. A column holding a transition from a newer build reads back as a
    /// room that announces one fewer thing, which is the failure that costs
    /// nothing; refusing the whole row would silence a room over one word.
    private static func announcements(in row: RoomPolicyRow) -> StateAnnouncements {
        StateAnnouncements(
            transitions: Set(
                KeywordColumn.decode(row.announcementTransitions)
                    .compactMap(StateAnnouncement.init(rawValue:))
            ),
            withinRecentConversation: row.announcementRecentWindow,
            delivery: AnnouncementDelivery(rawValue: row.announcementDelivery)
                ?? StateAnnouncements.off.delivery
        )
    }

    /// A room's 집중 시간 settings, which are inert until the switch is on.
    ///
    /// v18 gave every column the value a room that has never burned holds, and
    /// `burning_enabled` is one of them, so a row from before this existed reads
    /// back as a room that has never burned. Nothing here can make a room answer
    /// faster than its own settings say it does.
    private static func burning(in row: RoomPolicyRow) -> BurningMode {
        BurningMode(
            isEnabled: row.burningEnabled,
            chance: InterjectionChance(percent: row.burningChance),
            duration: JudgementInterval(
                shortest: row.burningDurationShortest,
                longest: row.burningDurationLongest
            ),
            cooldown: JudgementInterval(
                shortest: row.burningCooldownShortest,
                longest: row.burningCooldownLongest
            ),
            interjectionChance: InterjectionChance(percent: row.burningInterjectionChance),
            minimumInterval: row.burningMinimumInterval,
            judgementInterval: JudgementInterval(
                shortest: row.burningJudgementInterval,
                longest: row.burningJudgementIntervalLongest
            )
        )
    }

    /// The room's own style, or nil when it answers in the global one.
    ///
    /// The four columns always hold a readable style — the flag is what decides
    /// whether it is used — so a room switched to its own style cannot come back
    /// with half a style and half a default.
    private static func styleOverride(in row: RoomPolicyRow) -> ResponseStyle? {
        guard row.usesOwnStyle else { return nil }
        let defaults = ResponseStyle()
        return ResponseStyle(
            tone: row.styleTone,
            length: ResponseStyle.Length(rawValue: row.styleLength) ?? defaults.length,
            emojiUse: ResponseStyle.EmojiUse(rawValue: row.styleEmojiUse) ?? defaults.emojiUse,
            assertiveness: ResponseStyle.Assertiveness(rawValue: row.styleAssertiveness)
                ?? defaults.assertiveness
        )
    }
}
