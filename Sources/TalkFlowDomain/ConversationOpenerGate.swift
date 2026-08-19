import Foundation

/// Why a room is not being spoken to yet.
///
/// No `explanation` beside these, unlike `ReplyHoldReason`. None of them ever
/// reaches a person: every one of these holds is the expected answer, and the
/// sweep asks a minute at a time for hours, so recording them would bury the
/// rows somebody has to act on. What the user needs about this silence is on the
/// room's own screen, said once, rather than repeated into the timeline.
public enum ConversationOpenerHoldReason: Equatable, Sendable {
    case globalPause
    case accountUnverified
    case switchedOff
    case roomDisabled
    case outsideActiveHours
    case noConversation
    case spokeLast
    case stillTalking(quietFor: TimeInterval)
    /// TalkFlow spoke last and has opened as many times in a row as the room
    /// allows without the other side answering.
    case repeatLimitReached
    /// Inside 답변 활성화 시간 but outside the room's own 먼저 말 걸기 hours.
    case outsideOpenerHours
}

public enum ConversationOpenerVerdict: Equatable, Sendable {
    case open
    case hold(reason: ConversationOpenerHoldReason)
}

public struct ConversationOpenerRequest: Sendable {
    public let room: ChatRoom
    public let policy: RoomPolicy
    public let globalResponsesEnabled: Bool
    public let accountVerified: Bool
    /// Chronological, oldest first.
    public let recentMessages: [ChatMessage]
    /// When the model was last asked anything about this room, whatever it
    /// answered and whether it was a reply or an opener.
    public let lastJudgementAt: Date?
    /// How many times TalkFlow has opened since the other side's last message —
    /// openers only, not replies. `openerRepeatLimit` bounds this run of
    /// unanswered openers; a single message from anyone else resets it to zero.
    public let opensSinceTheyLastSpoke: Int
    public let now: Date
    public let calendar: Calendar
    /// Where in its range this cycle's wait falls, injected like the calendar so
    /// a test states the draw instead of hoping for one.
    public let roll: JudgementRoll

    public init(
        room: ChatRoom,
        policy: RoomPolicy,
        globalResponsesEnabled: Bool,
        accountVerified: Bool,
        recentMessages: [ChatMessage],
        lastJudgementAt: Date? = nil,
        opensSinceTheyLastSpoke: Int = 0,
        now: Date = Date(),
        calendar: Calendar = .current,
        roll: JudgementRoll = .fromCycleStart
    ) {
        self.room = room
        self.policy = policy
        self.globalResponsesEnabled = globalResponsesEnabled
        self.accountVerified = accountVerified
        self.recentMessages = recentMessages
        self.lastJudgementAt = lastJudgementAt
        self.opensSinceTheyLastSpoke = opensSinceTheyLastSpoke
        self.now = now
        self.calendar = calendar
        self.roll = roll
    }
}

/// Decides whether a room's turn to be spoken to first has come.
///
/// Separate from `ResponsePolicyEngine` because it answers a different question
/// from a different starting point: that engine is handed a message and asked
/// whether to answer it, this one is handed a silence and asked whether to break
/// it. Sharing a type would mean every rule in either growing a branch about
/// which of the two it belongs to.
///
/// The gates are the reply gates plus two of its own, and none of them may be
/// skipped because the room asked for openers. Turning this on says "you may
/// start a conversation here"; it does not withdraw 답변 활성화 시간 or the global
/// switch, and a room the user set to 끔 is a room the user switched off.
public struct ConversationOpenerGate: Sendable {
    /// How long a room has to have said nothing before opening a subject counts
    /// as opening one rather than interrupting.
    ///
    /// Half an hour. Shorter reads as barging in — people leave gaps of several
    /// minutes mid-conversation all the time, and a message that lands in one of
    /// those is answering a thread nobody finished. Much longer and the feature
    /// only ever fires into rooms that are dead rather than resting, which is not
    /// where a conversation is worth opening either.
    public static let defaultQuietPeriod: TimeInterval = 1800

    private let quietPeriod: TimeInterval

    public init(quietPeriod: TimeInterval = ConversationOpenerGate.defaultQuietPeriod) {
        self.quietPeriod = quietPeriod
    }

    public func evaluate(_ request: ConversationOpenerRequest) -> ConversationOpenerVerdict {
        guard request.globalResponsesEnabled else { return .hold(reason: .globalPause) }
        guard request.accountVerified else { return .hold(reason: .accountUnverified) }
        guard request.policy.conversationOpener.isOn else { return .hold(reason: .switchedOff) }

        // 멘션에만 응답 is not on this list. It says which messages get answered,
        // and a room that answers only when called can still be a room the user
        // wants opened — requiring 자동응답 would make one switch quietly change
        // what the room does about everybody else's messages.
        switch request.policy.responseMode {
        case .off, .detectOnly: return .hold(reason: .roomDisabled)
        case .mentionOnly, .automatic: break
        }

        // Both windows: the room's own 답변 활성화 시간, and 먼저 말 걸기's own hours on
        // top of it. An opener is the one thing the app says unprompted, so it is
        // held to both — speaking first at a time the room does not even answer is
        // the clearest way for this feature to be wrong.
        guard request.policy.activeHours.allows(request.now, calendar: request.calendar) else {
            return .hold(reason: .outsideActiveHours)
        }
        guard request.policy.conversationOpenerHours.allows(request.now, calendar: request.calendar) else {
            return .hold(reason: .outsideOpenerHours)
        }

        // The topic comes out of this room's own recent conversation, so a room
        // with nothing in it has nothing to open.
        guard let newest = request.recentMessages.last else { return .hold(reason: .noConversation) }

        // TalkFlow having spoken last used to end it here. A room may now set how
        // many times in a row it opens with no answer — said once, or a few times
        // over a day — counted from the other side's last message so a single reply
        // resets it and a room is never talked at forever. Zero, the default, keeps
        // the old rule: 내가 마지막이면 먼저 말 걸지 않음.
        //
        // `opensSinceTheyLastSpoke > 0` catches the same run when TalkFlow's own
        // opener is not yet the newest message the archive shows — a queued opener
        // echoes back a poll or two later, and without this the sweep would open
        // the same silence again every tick until it did, which is the loop the old
        // per-cycle record prevented.
        if newest.isFromMe || request.opensSinceTheyLastSpoke > 0 {
            guard request.policy.openerRepeatLimit > 0 else { return .hold(reason: .spokeLast) }
            guard request.opensSinceTheyLastSpoke < request.policy.openerRepeatLimit else {
                return .hold(reason: .repeatLimitReached)
            }
        }

        // The wait is a silence measured from the last message, whoever sent it —
        // not from the last model call, which a busy room's own replies kept
        // resetting so it never went quiet enough to open. How long is the room's
        // to set (down to a minute), drawn from its range so the cadence is not a
        // clock anyone can read.
        //
        // ④ 비활성 주기 정지: with the pause on, only the seconds inside 먼저 말 걸기's
        // own hours count toward that silence, so a room's wait is not run down by a
        // night when it was not allowed to speak — an opener falls due some way into
        // the hours reopening, not the instant they do. Off, the clock runs straight
        // through and the wait is the wall-clock gap.
        let silence = request.policy.openerCadencePausesOutsideHours
            ? request.policy.conversationOpenerHours.activeSeconds(
                from: newest.sentAt,
                to: request.now,
                calendar: request.calendar
            )
            : request.now.timeIntervalSince(newest.sentAt)
        let required = request.policy.conversationOpenerInterval
            .target(startingAt: newest.sentAt, roll: request.roll)?.wait
            ?? ConversationOpenerGate.defaultQuietPeriod
        guard silence >= required else { return .hold(reason: .stillTalking(quietFor: silence)) }
        return .open
    }
}
