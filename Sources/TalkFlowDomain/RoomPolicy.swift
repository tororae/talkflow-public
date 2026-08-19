import Foundation

public enum ResponseMode: String, CaseIterable, Equatable, Sendable {
    case off
    case detectOnly
    case mentionOnly
    case automatic

    public var title: String {
        switch self {
        case .off: "끔"
        case .detectOnly: "감지 전용"
        case .mentionOnly: "멘션에만 응답"
        case .automatic: "자동응답"
        }
    }
}

public enum DeliveryMode: String, CaseIterable, Equatable, Sendable {
    case draftOnly
    case autoSendWhenIdle
    /// Delivers without waiting for the user to step away.
    ///
    /// Sending drives KakaoTalk's UI, and reaching a window on another desktop
    /// means bringing the app forward — so this mode can interrupt work. It
    /// exists because waiting for idle means never replying while the user is at
    /// the machine, which is much of the day.
    case always

    public var title: String {
        switch self {
        case .draftOnly: "초안만"
        case .autoSendWhenIdle: "유휴 상태 자동 전송"
        case .always: "상시 전송"
        }
    }

    public var interruptsWork: Bool {
        self == .always
    }

    public var deliversAutomatically: Bool {
        self != .draftOnly
    }
}

/// Response rules for one chat room, keyed the way the rest of the app keys
/// everything: by account fingerprint and stable room id, never display name.
public struct RoomPolicy: Equatable, Sendable {
    public let accountFingerprint: String
    public let chatRoomID: String
    public var responseMode: ResponseMode
    /// How often this room bothers to ask about a message nobody addressed to
    /// it. 100% in every room, because asking is what the model's own judgement
    /// is for; 0% is what 자발 개입 꺼짐 was.
    ///
    /// A cost lever, and the only one that works by skipping rather than by
    /// waiting: `judgementInterval` keeps the messages it passes over and asks
    /// about them later, this one lets them go. Neither changes what the room
    /// says when it does answer — that is `answeringCondition`.
    public var interjectionChance: InterjectionChance
    public var deliveryMode: DeliveryMode
    /// The silence after a reply, in force only while this room judges every
    /// message as it arrives. It skips whatever lands inside it, which is the
    /// cheap approximation of what `judgementInterval` does properly.
    public var minimumInterval: TimeInterval
    /// How often this room is judged at all. `즉시` — every room's starting
    /// value — means each new message is judged as it arrives.
    ///
    /// Anything else means messages accumulate and the model is asked once per
    /// cycle about all of them. That is the difference between one call and one
    /// call per message in a room that talks, and it is the only setting here
    /// that changes what TalkFlow spends rather than what it says.
    ///
    /// The cycle is measured either in seconds or in messages from other people,
    /// and never in both — see `JudgementInterval.Measure`. Rooms move at wildly
    /// different speeds, so neither unit can be the right one everywhere.
    ///
    /// It supersedes `minimumInterval` while it is on: both bound how often a
    /// room may answer, and two settings meaning the same thing with different
    /// answers is worse than one. The interval wins because it keeps the messages
    /// it passes over instead of dropping them.
    public var judgementInterval: JudgementInterval
    /// When this room may answer at all.
    public var activeHours: ReplyActiveHours
    /// Whether photos from this room may be attached to the AI call.
    ///
    /// Off unless the room asks for it, because this is the one setting that
    /// widens what leaves the Mac. The conversation's text already goes to the
    /// provider; a picture is new material, and it carries whatever else
    /// happened to be in frame. Only the user can weigh that, and the answer
    /// differs from room to room, so it is asked per room rather than once.
    public var readsPhotos: Bool
    /// Whether the AI may use live web search when composing a reply here.
    ///
    /// Off unless the room asks for it, the same rule as 사진 함께 읽기: it widens
    /// what leaves the Mac. The conversation's text already goes to the provider,
    /// but with this on the model turns that text into web search queries — a
    /// fragment of this room's talk reaches the open web, not only the model. The
    /// answer differs from room to room, so it is asked per room.
    public var webSearch: Bool
    /// Whether the app may open a link from this room and read the page into the
    /// reply prompt.
    ///
    /// Off unless the room asks, the same rule as 사진 함께 읽기 and 웹 검색: it
    /// widens what leaves the Mac. The app fetches the page itself and feeds only
    /// its text to the model, which never browses — but a URL someone pasted is
    /// still opened on the account's behalf, and where that is welcome differs
    /// from room to room.
    public var readsLinks: Bool
    /// Whether TalkFlow may open a conversation here on its own.
    ///
    /// Off in every room, including rooms configured long before this existed. It
    /// is the only setting that makes the app speak without being spoken to, so
    /// nothing may turn it on by implication — not 자동응답, not 상시 전송, not
    /// 끼어들기 확률 100%. See `ConversationOpener` for why delivery is a second
    /// choice inside it rather than inherited from `deliveryMode`.
    public var conversationOpener: ConversationOpener
    /// How long this room waits between openers, drawn from a range so the
    /// cadence is not a clock anyone can read.
    ///
    /// Its own value rather than a share of `judgementInterval`: that one bounds
    /// what the room spends answering people, this one bounds how often the room
    /// hears from TalkFlow unasked, and a number that suits one is nowhere near
    /// the number that suits the other.
    public var conversationOpenerInterval: JudgementInterval
    /// The hours 먼저 말 걸기 is allowed in, on top of 답변 활성화 시간: an opener
    /// fires only when both windows are open. `.always` means the room's own
    /// answering hours are the only limit, which is how every room behaved before.
    public var conversationOpenerHours: ReplyActiveHours
    /// How many times in a row TalkFlow may open when it spoke last and nobody has
    /// answered since. Zero keeps the old rule — 내가 마지막이면 먼저 말 걸지 않음.
    /// Counted from the other side's last message, so a single reply resets it and
    /// a room can never be talked at forever.
    public var openerRepeatLimit: Int
    /// Whether a repeat opener carries the previous subject on or starts a new one.
    public var openerRepeatTopic: OpenerRepeatTopic
    /// Whether the opener's silence clock pauses outside its hours. Off: the clock
    /// runs through the night and an opener is due the moment the hours reopen. On:
    /// the wait counts only inside the hours, so it starts fresh when they reopen.
    public var openerCadencePausesOutsideHours: Bool
    /// A standing note handed to the opener prompt — 「요즘 하는 프로젝트 얘기 꺼내」.
    /// Nil or empty leaves the line out entirely rather than sending a blank one.
    public var openerPromptHint: String?
    /// Extra words that count as a call in this room, added to the account's own
    /// name and the keywords registered in 설정 rather than replacing them.
    ///
    /// Empty by default, because the part nobody should have to configure — the
    /// name — is detected. This exists for the word that only means the account
    /// inside one room: a project's codename, a bot alias a group made up.
    /// Registering that globally would have every other room answer to it.
    public var responseKeywords: [String]
    /// This room's own 답변 조건, or nil to judge by the one registered in 설정.
    ///
    /// Nil rather than a copy of the global text, so a room that follows along
    /// keeps following when the global changes. See `answeringCondition(global:)`
    /// for why an override that is empty is still an override.
    public var answeringConditionOverride: AnsweringCondition?
    /// This room's own 말투·길이·이모지·적극성, or nil to answer in the global style.
    ///
    /// Nil in every room, including rooms configured before this existed: the
    /// style they have been answering in is the global one, and an upgrade may
    /// not freeze a copy of today's global into every room.
    public var responseStyleOverride: ResponseStyle?
    /// Whether TalkFlow keeps a standing note about this room and puts it in
    /// every reply prompt.
    ///
    /// On, unlike 사진 함께 읽기 and 먼저 말 걸기. Those are off because one widens
    /// what leaves the Mac and the other makes the app speak unasked; this one
    /// does neither — the conversation it summarises is already going to the
    /// provider on every reply — and without it the model answers a months-long
    /// relationship from thirty lines.
    ///
    /// It is still a switch rather than nothing, because what it leaves behind is
    /// a written description of real people. Turning it off deletes the note as
    /// well as stopping the refreshes; a room the user told TalkFlow to forget
    /// should not keep a file about it.
    public var remembersConversation: Bool
    /// Whether a KakaoTalk 답장 aimed at one of this account's messages counts as
    /// being called.
    ///
    /// On by default, unlike 먼저 말 걸기 which every existing room had to opt
    /// into. That one was the app doing something nobody asked for; this one is
    /// the app noticing it was addressed. A room that answers when its name is
    /// typed and ignores a direct reply to its own message is not being cautious,
    /// it is being obtuse — and the person who replied is waiting either way.
    public var answersReplies: Bool
    /// 집중 시간 — see `BurningMode`. Off in every room.
    public var burning: BurningMode
    /// 상태 알림 — see `StateAnnouncements`. Off in every room.
    public var announcements: StateAnnouncements
    /// Whether this room takes part in 사람 기억: its conversation feeds the notes
    /// kept about the people in it, and those notes ride along when one of them
    /// speaks.
    ///
    /// Off in every room, and not folded into `remembersConversation` even though
    /// that is the switch it would otherwise belong under. That one is on
    /// everywhere by default, so folding this in would start writing files about
    /// real people in every room the moment this shipped, chosen by nobody. This
    /// widens what leaves the Mac, which in this app means it arrives off — the
    /// rule 사진 함께 읽기 and 먼저 말 걸기 already follow.
    public var remembersPeople: Bool

    public init(
        accountFingerprint: String,
        chatRoomID: String,
        responseMode: ResponseMode,
        interjectionChance: InterjectionChance = .always,
        deliveryMode: DeliveryMode = .draftOnly,
        minimumInterval: TimeInterval = 300,
        judgementInterval: JudgementInterval = .immediate,
        activeHours: ReplyActiveHours = .always,
        readsPhotos: Bool = false,
        webSearch: Bool = false,
        readsLinks: Bool = false,
        conversationOpener: ConversationOpener = .off,
        conversationOpenerInterval: JudgementInterval = JudgementIntervalInput.conversationOpener.time.suggested,
        conversationOpenerHours: ReplyActiveHours = .always,
        openerRepeatLimit: Int = 0,
        openerRepeatTopic: OpenerRepeatTopic = .carryOn,
        openerCadencePausesOutsideHours: Bool = false,
        openerPromptHint: String? = nil,
        responseKeywords: [String] = [],
        answeringConditionOverride: AnsweringCondition? = nil,
        responseStyleOverride: ResponseStyle? = nil,
        remembersConversation: Bool = true,
        answersReplies: Bool = true,
        burning: BurningMode = .off,
        announcements: StateAnnouncements = .off,
        remembersPeople: Bool = false
    ) {
        self.accountFingerprint = accountFingerprint
        self.chatRoomID = chatRoomID
        self.responseMode = responseMode
        self.interjectionChance = interjectionChance
        self.deliveryMode = deliveryMode
        self.minimumInterval = minimumInterval
        self.judgementInterval = judgementInterval
        self.activeHours = activeHours
        self.readsPhotos = readsPhotos
        self.webSearch = webSearch
        self.readsLinks = readsLinks
        self.conversationOpener = conversationOpener
        self.conversationOpenerInterval = conversationOpenerInterval
        self.conversationOpenerHours = conversationOpenerHours
        self.openerRepeatLimit = openerRepeatLimit
        self.openerRepeatTopic = openerRepeatTopic
        self.openerCadencePausesOutsideHours = openerCadencePausesOutsideHours
        self.openerPromptHint = openerPromptHint
        self.responseKeywords = responseKeywords
        self.answeringConditionOverride = answeringConditionOverride
        self.responseStyleOverride = responseStyleOverride
        self.remembersConversation = remembersConversation
        self.answersReplies = answersReplies
        self.burning = burning
        self.announcements = announcements
        self.remembersPeople = remembersPeople
    }

    /// Whether this room accumulates messages and answers them together.
    public var judgesInBatches: Bool {
        judgementInterval.batches
    }

    /// Whether this room does anything at all with an incoming message.
    ///
    /// `감지 전용` sits with `끔` because the pipeline skips both at the same
    /// place. Asked by everything that spends money on a room, so that a room the
    /// user switched off cannot be given a reason to cost something.
    public var answersMessages: Bool {
        responseMode != .off && responseMode != .detectOnly
    }

    /// Whether an opener written for this room may go out without a person
    /// pressing send.
    ///
    /// Both switches, never either. The opener's own choice is the consent to
    /// speak unasked; the room's 전송 방식 is the consent to send at all, and this
    /// cannot be the setting that quietly widens that one.
    public var openerDeliversAutomatically: Bool {
        conversationOpener == .delivers && deliveryMode.deliversAutomatically
    }

    /// A room TalkFlow has never been told about answers nobody.
    ///
    /// Group rooms default to mention-only rather than off so that turning a room
    /// on is one switch instead of two, but neither type ever sends before the
    /// user asks for it. 끼어들기 확률 takes its own default of 100 and is simply
    /// not consulted until a room is put on 자동응답 — the mode is the consent, and
    /// a second dial silently at zero was how 자발 개입 kept rooms quiet for
    /// reasons nobody could see.
    public static func makeDefault(
        accountFingerprint: String,
        room: ChatRoom
    ) -> RoomPolicy {
        RoomPolicy(
            accountFingerprint: accountFingerprint,
            chatRoomID: room.id,
            responseMode: .off,
            deliveryMode: .draftOnly
        )
    }

    /// The mode a room takes when the user first enables it.
    public static func initialEnabledMode(for room: ChatRoom) -> ResponseMode {
        room.kind == .group ? .mentionOnly : .automatic
    }
}
