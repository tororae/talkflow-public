import Foundation

public struct ReplyEvaluationRequest: Sendable {
    public let room: ChatRoom
    public let policy: RoomPolicy
    public let globalResponsesEnabled: Bool
    public let accountVerified: Bool
    /// Chronological, oldest first.
    public let recentMessages: [ChatMessage]
    public let lastReplyAt: Date?
    /// When the model was last asked about this room, whatever it answered.
    ///
    /// Separate from `lastReplyAt` because a batch is paced by what it costs, not
    /// by what it produced. Most calls in the busiest rooms come back with
    /// nothing; anchoring the interval on replies would let such a room keep
    /// paying for a call on every sync.
    public let lastJudgementAt: Date?
    /// The name KakaoTalk shows for this account. Detected, never configured:
    /// being called by your own name is not a setting a user should have to
    /// find, and a room that waits for one stays silent forever.
    public let accountNickname: String?
    /// The extra words registered in 설정, in force in every room.
    public let responseKeywords: [String]
    public let now: Date
    /// The clock the room's active hours are read on. Injected so a test can
    /// state "23:30 in Seoul" instead of depending on where the machine is.
    public let calendar: Calendar
    /// Where in its range one batching cycle's wait falls. Carried like the
    /// calendar, for the same reason: a test states the draw rather than hoping
    /// for one, and the engine stays a function of what it was handed.
    public let judgementRoll: JudgementRoll
    /// Whether this judgement clears the room's 끼어들기 확률. Carried for the same
    /// reason as `judgementRoll`, and drawn the same way: from the subject rather
    /// than freshly, so asking twice cannot get two answers.
    public let interjectionRoll: InterjectionRoll
    /// The message a previous look at this room already committed to answering
    /// from, when this is a second look at the same run.
    ///
    /// Only 뒷말 대기 sets it. That wait re-reads the room a few seconds later, by
    /// which time the newest message may have moved on — and an unpinned second
    /// look would draw a fresh 끼어들기 roll for a run the first look had already
    /// accepted. That is a coin flipped twice about one answer, which is exactly
    /// what a percentage must never do.
    public let answeringFrom: String?

    public init(
        room: ChatRoom,
        policy: RoomPolicy,
        globalResponsesEnabled: Bool,
        accountVerified: Bool,
        recentMessages: [ChatMessage],
        lastReplyAt: Date? = nil,
        lastJudgementAt: Date? = nil,
        accountNickname: String? = nil,
        responseKeywords: [String] = [],
        now: Date = Date(),
        calendar: Calendar = .current,
        judgementRoll: JudgementRoll = .fromCycleStart,
        interjectionRoll: InterjectionRoll = .fromJudgedRun,
        answeringFrom: String? = nil
    ) {
        self.room = room
        self.policy = policy
        self.globalResponsesEnabled = globalResponsesEnabled
        self.accountVerified = accountVerified
        self.recentMessages = recentMessages
        self.lastReplyAt = lastReplyAt
        self.lastJudgementAt = lastJudgementAt
        self.accountNickname = accountNickname
        self.responseKeywords = responseKeywords
        self.now = now
        self.calendar = calendar
        self.judgementRoll = judgementRoll
        self.interjectionRoll = interjectionRoll
        self.answeringFrom = answeringFrom
    }

    /// What the 끼어들기 draw is made for: this room, and the oldest message the
    /// judgement is answerable for.
    ///
    /// The room is in the key so two rooms do not skip and ask in lockstep. The
    /// message makes it one draw per judgement — per message where the room
    /// judges immediately, per cycle where it batches, since everything one cycle
    /// accumulated shares the same oldest message.
    public var interjectionKey: String {
        "\(room.id)/\(answeringFrom ?? judgementScope.first?.id ?? "")"
    }

    /// The three sources of a call, assembled in one place so no caller can
    /// leave one of them out.
    public var callSigns: CallSigns {
        CallSigns(nickname: accountNickname, globalKeywords: responseKeywords, policy: policy)
    }

    /// The messages this judgement is answerable for.
    ///
    /// A room judging every message is answerable for the one that just arrived.
    /// A room judging in batches is answerable for everything since it was last
    /// asked anything — otherwise a call that landed early in the interval would
    /// be forgotten by the time the room is allowed to speak, and the batch would
    /// only ever see whichever message happened to be last.
    public var judgementScope: [ChatMessage] {
        guard policy.judgesInBatches else { return Array(recentMessages.suffix(1)) }
        guard let lastJudgementAt else { return recentMessages }

        // KakaoTalk's timestamps and our own clock are not the same clock. If
        // they disagree far enough to empty the batch, the newest message still
        // gets judged rather than the room going quiet for reasons nobody can see.
        let since = recentMessages.filter { $0.sentAt > lastJudgementAt }
        return since.isEmpty ? Array(recentMessages.suffix(1)) : since
    }

    /// Whether somebody used KakaoTalk's own 답장 on something this account said.
    ///
    /// The strongest call there is, and the only one that needs no setting up: a
    /// person picked the message out of the room and answered it. A keyword can
    /// be missing, a name can be spelled another way, and neither excuse applies
    /// here.
    ///
    /// Only messages inside the window can be recognised as the thing replied to.
    /// A reply to something said last week reads as no reply at all, which is the
    /// right way to be wrong — a room that answered because it could not see what
    /// was quoted would be answering something nobody can read either.
    public var repliesToThisAccount: Bool {
        let mine = Set(recentMessages.filter(\.isFromMe).map(\.id))
        guard !mine.isEmpty else { return false }
        return judgementScope.contains { message in
            guard !message.isFromMe, let answered = message.replyToMessageID else { return false }
            return mine.contains(answered)
        }
    }

    /// How much conversation this cycle has accumulated, for a 판단 주기 counted in
    /// messages rather than on a clock.
    ///
    /// **Other people's messages only.** Two reasons, and the second is the one
    /// that decides it. A user typing in the room is handling it themselves, and
    /// counting what they say would push TalkFlow to speak sooner exactly when it
    /// is least wanted. And a reply TalkFlow sends arrives back in the archive as
    /// one of ours: counting those would let an answer advance the cycle that
    /// produces the next answer, which is a room talking itself into a rhythm
    /// nobody set.
    ///
    /// Not derived from `judgementScope`, which falls back to the newest message
    /// when the two clocks disagree. That fallback exists so a batch is never
    /// empty; borrowed here it would count a message towards a cycle that has not
    /// seen one.
    public var accumulatedMessageCount: Int {
        recentMessages.filter { message in
            guard !message.isFromMe else { return false }
            guard let lastJudgementAt else { return true }
            return message.sentAt > lastJudgementAt
        }
        .count
    }
}
