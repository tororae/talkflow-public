import Foundation
import TalkFlowDomain

/// The pipeline that runs after every sync: for each room that changed, apply
/// the deterministic rules, ask the model only about survivors, and record what
/// was decided either way.
///
/// It stops at the draft. Whether a draft is ever delivered is the send
/// coordinator's decision, kept separate because sending cannot be undone.
public struct DraftRepliesForChangedRooms: Sendable {
    /// How much of a conversation the model sees. Enough for a thread to make
    /// sense, short enough that a whole chat history never leaves the machine.
    public static let contextMessageLimit = ConversationWindow.messageLimit

    /// How many rooms may be drafted at once in one sweep. Each room's turn is a
    /// Codex process and a model call — a web search or a rendered page on top —
    /// so this is the ceiling that keeps a busy sweep from becoming a burst of
    /// processes and a provider rate limit. It bounds generation only; sending
    /// stays serial in the send queue, which this pipeline never touches. The one
    /// place to change the number, held conservative on purpose — the drafting
    /// loop in TalkFlowModels reads the same ceiling now that jobs run per room.
    public static let maxConcurrentRooms = 10

    let connection: any KakaoConnection
    let policyStore: any RoomPolicyStore
    let settingsStore: any AppSettingsStore
    let actionLog: any AgentActionLog
    let generator: any ReplyGenerator
    let sendStore: (any PendingSendStore)?
    /// Optional because a build without it still drafts replies. Photos are
    /// context, not the answer.
    let photoSource: (any MessagePhotoSource)?
    /// Optional like the photo source: a build without it drafts replies without
    /// ever opening a link. Only rooms that turned link reading on reach it.
    let linkSource: (any MessageLinkSource)?
    /// Read on the reply path, never written on it. Whatever the note says at
    /// this instant rides along; if a refresh is due, it happens on its own
    /// schedule and this reply goes out with the note as it stands.
    let summaryStore: (any ConversationSummaryStore)?
    /// Optional like the others: a build without it drafts replies on each
    /// room's own settings, which is what every room does today anyway.
    let burningStore: (any BurningStateStore)?
    /// Injected so a test states the draw instead of hoping for one.
    let burningRoll: BurningRoll
    /// Read on the reply path and written nowhere near it. Notes are maintained
    /// by the 채팅방 요약 refresh, which runs seven times a day against this path's
    /// two thousand — so a reply reads whatever is written and never rewrites it.
    let personNotes: (any PersonNoteStore)?
    let settlingDelay: TimeInterval
    /// Read in `draft`, which is the only place a reply ever waits now.
    let followUpDelay: TimeInterval
    /// Injected so a test can let the wait pass without spending it.
    let pause: @Sendable (TimeInterval) async -> Void
    private let engine = ResponsePolicyEngine()

    public init(
        connection: any KakaoConnection,
        policyStore: any RoomPolicyStore,
        settingsStore: any AppSettingsStore,
        actionLog: any AgentActionLog,
        generator: any ReplyGenerator,
        sendStore: (any PendingSendStore)? = nil,
        photoSource: (any MessagePhotoSource)? = nil,
        linkSource: (any MessageLinkSource)? = nil,
        summaryStore: (any ConversationSummaryStore)? = nil,
        burningStore: (any BurningStateStore)? = nil,
        burningRoll: BurningRoll = .random,
        personNotes: (any PersonNoteStore)? = nil,
        settlingDelay: TimeInterval = SendGate.defaultSettlingDelay,
        followUpDelay: TimeInterval = FollowUpWait.defaultDelay,
        pause: @escaping @Sendable (TimeInterval) async -> Void = {
            try? await Task.sleep(for: .seconds($0))
        }
    ) {
        self.connection = connection
        self.policyStore = policyStore
        self.settingsStore = settingsStore
        self.actionLog = actionLog
        self.generator = generator
        self.sendStore = sendStore
        self.photoSource = photoSource
        self.linkSource = linkSource
        self.summaryStore = summaryStore
        self.burningStore = burningStore
        self.burningRoll = burningRoll
        self.personNotes = personNotes
        self.settlingDelay = settlingDelay
        self.followUpDelay = followUpDelay
        self.pause = pause
    }

    /// `detectedAt` and `synchronizedAt` are the sync's own instants, carried in
    /// so each recorded action can say how long the message had already been
    /// waiting before this pipeline was handed it. Defaulting them to now means a
    /// caller that has no sync to name — a test, a manual run — records a
    /// timeline that starts here instead of one that lies about a delay.
    @discardableResult
    public func callAsFunction(
        changedChatRoomIDs: [String],
        detectedAt: Date? = nil,
        synchronizedAt: Date = Date()
    ) async -> [AgentAction] {
        guard !changedChatRoomIDs.isEmpty else { return [] }
        guard case let .connected(account) = await connection.status() else { return [] }
        guard let globalEnabled = try? await settingsStore.globalResponsesEnabled(), globalEnabled else {
            return []
        }

        // Read once for the whole sweep. Both are global values a room may
        // override, and resolving them per room is the room's own business.
        let style = (try? await settingsStore.responseStyle()) ?? ResponseStyle()
        let condition = (try? await settingsStore.answeringCondition()) ?? .empty
        let rooms = (try? await connection.chatRooms()) ?? []
        let changed = Set(changedChatRoomIDs)

        // Every room in this sweep shares the same two opening stamps, because
        // they share the one sync that caused it. What they stop sharing is the
        // next stamp: the rooms are processed one after another and each model
        // call is seconds long, so the second room's 규칙 판단 lands well after
        // the first room's — which is exactly the queueing this record exists to
        // make visible.
        var detection = ActionTimeline()
        if let detectedAt { detection.stamp(.detected, at: detectedAt) }
        detection.stamp(.synchronized, at: synchronizedAt)
        // A `let` snapshot for the concurrent tasks to capture: `detection` is a
        // var only to take the two stamps above, and handing a mutable value into
        // sending closures is exactly the data race the compiler refuses.
        let sweepTimeline = detection

        // Rooms are drafted concurrently now, up to `maxConcurrentRooms` at once,
        // rather than one after another. A room whose reply needs a web search or
        // a rendered page used to make every other room in the sweep wait behind
        // it; each room is its own model call with nothing shared between them, so
        // they run together and the sweep costs its slowest room instead of their
        // sum.
        //
        // A room is still drafted once per sweep and sweeps do not overlap, so the
        // same room never runs twice at once. And this only drafts and enqueues —
        // the send queue stays the single serial writer to KakaoTalk — so nothing
        // here can put two messages on screen at the same time.
        let targets = rooms.filter { changed.contains($0.id) }
        var recorded: [AgentAction] = []
        await withTaskGroup(of: AgentAction?.self) { group in
            var pending = targets.makeIterator()
            var running = 0
            while running < Self.maxConcurrentRooms, let room = pending.next() {
                running += 1
                group.addTask {
                    await self.process(
                        room: room,
                        account: account,
                        style: style,
                        condition: condition,
                        timeline: sweepTimeline
                    )
                }
            }
            // As each room finishes, start the next one waiting — a sliding window
            // of `maxConcurrentRooms`, not a batch that stalls on its slowest member.
            while let action = await group.next() {
                if let action { recorded.append(action) }
                guard let room = pending.next() else { continue }
                group.addTask {
                    await self.process(
                        room: room,
                        account: account,
                        style: style,
                        condition: condition,
                        timeline: sweepTimeline
                    )
                }
            }
        }
        return recorded
    }

    private func process(
        room: ChatRoom,
        account: AccountProfile,
        style: ResponseStyle,
        condition: AnsweringCondition,
        timeline: ActionTimeline
    ) async -> AgentAction? {
        guard let stored = try? await policyStore.policy(for: room, accountFingerprint: account.fingerprint),
              stored.responseMode != .off,
              stored.responseMode != .detectOnly
        else {
            return nil
        }

        // Read once, here, and used for the whole of this room's turn. A burn
        // that expired between the judgement and the roll would otherwise be
        // burning for one and over for the other.
        let now = Date()
        let burning = await burning(for: room, account: account, policy: stored, at: now)
        let policy = burning.policy

        // Before the room is judged, and before the hours gate turns it away: a
        // room whose window just shut is exactly the room that owes a goodbye,
        // and the judgement below would hold it with `.outsideActiveHours`
        // without ever reaching this.
        if let crossed = await announceHoursChange(
            room: room,
            account: account,
            policy: policy,
            style: style,
            at: now
        ) {
            return crossed
        }

        // Before judging, because a burn that has just ended is not a burn: the
        // goodbye goes out on this room's own settings, and letting the reply run
        // first would answer once more at burning speed after saying it was gone.
        if let ended = await announceEndedBurn(
            room: room,
            account: account,
            policy: policy,
            style: style,
            state: burning.state,
            at: now
        ) {
            return ended
        }

        guard let judgement = await judge(room: room, account: account, policy: policy, style: style) else {
            return nil
        }
        let timeline = timeline.stamping(.judged)

        // No wait here any more. Whether the person is still typing is a reading
        // of the conversation, and it is now read by the thing that reads the
        // conversation — see `draft`, which asks the model and waits on its
        // answer. What used to stand here was a list of Korean connectives and a
        // five-second burst window, deciding on the app's own authority whether
        // to pause before the model had said anything at all.

        switch judgement.evaluation {
        case let .hold(reason):
            guard let latest = judgement.messages.last else { return nil }
            return await recordHoldIfNotable(
                reason,
                room: room,
                account: account,
                latest: latest,
                timeline: timeline
            )
        case let .ask(trigger, triggerMessageID):
            let resolvedStyle = policy.responseStyle(global: style)
            let resolvedCondition = policy.answeringCondition(global: condition)

            // A room that reads the web and delivers on its own answers in two
            // beats: a first tool-less call that may defer for a search and say so
            // in its own words, then the searched answer. The deciding call is the
            // reply judgment itself — it sees its own recent replies and any link
            // content already in the prompt — so it defers only for a genuinely new
            // lookup, not a topic it just answered or a link it can already read.
            if policy.webSearch, policy.deliveryMode.deliversAutomatically {
                return await answerMaybeSearching(
                    trigger: trigger,
                    triggerMessageID: triggerMessageID,
                    answeredFromID: judgement.answeredFromID,
                    room: room,
                    account: account,
                    policy: policy,
                    window: ConversationWindow.bounded(judgement.messages),
                    style: resolvedStyle,
                    condition: resolvedCondition,
                    timeline: timeline
                )
            }

            // Everything else in one call: a room that reads the web but leaves
            // replies as drafts searches inline (a person reviews before sending,
            // so there is nobody to acknowledge to); every other room does not
            // search at all.
            let searchStage: SearchStage = policy.webSearch ? .inline : .none
            let action = await draftAllowingFollowUp(
                trigger: trigger,
                triggerMessageID: triggerMessageID,
                answeredFromID: judgement.answeredFromID,
                room: room,
                account: account,
                policy: policy,
                messages: judgement.messages,
                style: resolvedStyle,
                globalStyle: style,
                condition: resolvedCondition,
                searchStage: searchStage,
                timeline: timeline
            )
            // Rolled against the room's own settings, not the burned ones. A
            // room already burning cannot start a second burn — its cooldown
            // says so — and reading the trigger chance off a policy this feature
            // just rewrote is how a setting comes to mean something different
            // once it is in force.
            if action?.kind == .drafted,
               await startBurnIfDrawn(
                   for: room,
                   account: account,
                   policy: stored,
                   after: burning.state,
                   at: now
               ) != nil {
                // Said after the reply rather than instead of it. The message
                // that started the burn still deserves its answer, and a hello
                // arriving in place of it would read as the app ignoring the
                // person who spoke.
                _ = await announceStartedBurn(
                    room: room,
                    account: account,
                    policy: stored,
                    style: style,
                    at: now
                )
            }
            return action
        }
    }

    /// One reading of a room: what it holds now, and what the rules make of it.
    ///
    /// Internal rather than private because 뒷말 대기 takes a second reading after
    /// the wait, and that lives in `+FollowUp` — the rules a reply passed ten
    /// seconds ago all have to hold again before it is sent.
    struct Judgement {
        let messages: [ChatMessage]
        let evaluation: ReplyEvaluation
        /// The oldest message this reply will be a response to. Taken from the
        /// request rather than worked out here, so the run recorded and the run
        /// judged are the same run by construction.
        ///
        /// It survives 뒷말 대기 unchanged, which is the point of carrying it: a
        /// wait adds to the end of a run rather than starting a new one, and a
        /// reply that re-anchored on whatever arrived last would name that one
        /// message on a record covering the whole exchange.
        let answeredFromID: String?
    }

    /// Nil when the room cannot be read, or when its newest message has already
    /// been judged — re-asking would cost a model call and could produce a second
    /// reply to one message.
    func judge(
        room: ChatRoom,
        account: AccountProfile,
        policy: RoomPolicy,
        style: ResponseStyle,
        answering earlier: String? = nil
    ) async -> Judgement? {
        guard let messages = try? await connection.recentMessages(in: room, limit: Self.contextMessageLimit),
              let latest = messages.last
        else {
            return nil
        }

        if (try? await actionLog.hasAction(chatRoomID: room.id, triggerMessageID: latest.id)) == true {
            return nil
        }

        let lastReplyAt = try? await actionLog.lastReplyDate(
            chatRoomID: room.id,
            accountFingerprint: account.fingerprint
        )
        let lastJudgementAt = try? await actionLog.lastJudgementDate(
            chatRoomID: room.id,
            accountFingerprint: account.fingerprint
        )

        // The room's own name, not the account's. KakaoTalk lets one account go
        // by a different name in each room, and the archive records it per
        // message — so a room where the user renamed themselves was answering to
        // a name nobody there uses, and ignoring `@` calls by the name they do.
        // One indexed read per judgement, falling back to the account-wide name
        // for a room this account has never spoken in.
        let nickname = await connection.accountNickname(in: room) ?? account.nickname

        let request = ReplyEvaluationRequest(
            room: room,
            policy: policy,
            globalResponsesEnabled: true,
            accountVerified: true,
            recentMessages: messages,
            lastReplyAt: lastReplyAt ?? nil,
            lastJudgementAt: lastJudgementAt ?? nil,
            accountNickname: nickname,
            responseKeywords: style.responseKeywords,
            answeringFrom: earlier
        )

        return Judgement(
            messages: messages,
            evaluation: engine.evaluate(request),
            answeredFromID: request.judgementScope.first?.id
        )
    }
}
