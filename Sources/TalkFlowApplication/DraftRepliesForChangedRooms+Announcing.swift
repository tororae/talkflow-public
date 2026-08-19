import Foundation
import TalkFlowDomain

/// 상태 알림 — the room being told that this account started or stopped being
/// around.
///
/// Rides the reply pass rather than a timer of its own, like everything else
/// here. A burn that ended while the Mac was asleep is announced the next time
/// the room is looked at, which is also the next time there is a conversation
/// for the line to land in — the two are the same moment and there is nothing to
/// schedule.
extension DraftRepliesForChangedRooms {
    /// Says the one thing this room is owed, or nothing.
    ///
    /// One per pass at most. A burn that started and ended between two syncs
    /// would otherwise produce a hello and a goodbye in the same breath, which is
    /// worse than having said neither.
    func announce(
        _ transition: StateAnnouncement,
        room: ChatRoom,
        account: AccountProfile,
        policy: RoomPolicy,
        style: ResponseStyle,
        at now: Date
    ) async -> AgentAction? {
        guard policy.announcements.announces(transition) else { return nil }
        guard let messages = try? await connection.recentMessages(
            in: room,
            limit: Self.contextMessageLimit
        ) else {
            return nil
        }
        // The gate, and the reason this is not a bot posting 「왔다」 into an empty
        // room every morning. A line about somebody arriving or leaving is only
        // worth anything while there is a conversation for it to land in.
        guard policy.announcements.worthTelling(
            lastMessageAt: messages.last?.sentAt,
            at: now
        ) else {
            return nil
        }

        let window = ConversationWindow.bounded(messages)
        let request = ReplyDraftRequest(
            room: room,
            intent: .announce(transition),
            trigger: .spontaneous,
            triggerMessageID: window.messages.last?.id ?? "",
            recentMessages: window.messages,
            style: style,
            answeringCondition: .empty,
            conversationSummary: nil,
            omittedMessageCount: window.omittedCount
        )

        let draft = try? await generator.generateReply(request)
        guard let text = draft?.usableText else {
            // Recorded, though it says nothing. This was left out at first on the
            // reasoning that declining is the usual answer and a row per
            // transition would bury the ones that spoke — which is true of
            // replies, where a room declines hundreds of times a day, and false
            // here. A burn ends a few times a day at most.
            //
            // What it cost: the first burn to run with this shipped ended, the
            // end was marked as announced, and no row appeared anywhere. From
            // outside there was no way to tell a model that chose to stay quiet
            // from a call that failed. Silence has to be legible or the switch
            // cannot be trusted.
            try? await actionLog.record(
                AgentAction(
                    accountFingerprint: account.fingerprint,
                    chatRoomID: room.id,
                    chatRoomName: room.displayName,
                    kind: .held,
                    detail: draft == nil
                        ? "\(transition.recordLabel) 알림을 만들지 못했습니다."
                        : "\(transition.recordLabel) 알림: \(draft?.usableDeclineReason ?? "할 말이 없다고 판단했습니다.")",
                    contextMessageCount: window.messages.count
                )
            )
            return nil
        }

        await queueAnnouncement(text, room: room, account: account, policy: policy, at: now)
        return AgentAction(
            accountFingerprint: account.fingerprint,
            chatRoomID: room.id,
            chatRoomName: room.displayName,
            kind: .opened,
            replyText: text,
            detail: "\(transition.recordLabel) 알림을 만들어 전송 대기열에 넣었습니다.",
            contextMessageCount: window.messages.count
        )
    }

    /// Never more permissive than the room's 전송 방식.
    ///
    /// Both switches, never either — the same rule 먼저 말 걸기 follows. Choosing
    /// 전송까지 here is agreeing that TalkFlow may speak unasked; the room's
    /// delivery mode is the separate agreement that it may send at all, and this
    /// is not the setting that gets to widen it.
    private func queueAnnouncement(
        _ text: String,
        room: ChatRoom,
        account: AccountProfile,
        policy: RoomPolicy,
        at now: Date
    ) async {
        guard policy.announcements.delivery == .delivers,
              policy.deliveryMode.deliversAutomatically,
              let sendStore
        else {
            return
        }
        try? await sendStore.enqueue(
            PendingSend(
                accountFingerprint: account.fingerprint,
                chatRoomID: room.id,
                chatRoomName: room.displayName,
                triggerMessageID: "announcement-\(now.timeIntervalSince1970)",
                text: text,
                eligibleAt: now
            )
        )
    }
}

extension DraftRepliesForChangedRooms {
    /// The goodbye a finished burn is owed, said once.
    ///
    /// `hasJustEnded` is asked rather than fired on a deadline, so a burn that
    /// expired while the Mac was asleep still gets its last word — and
    /// `markAnnounced` is what stops it getting one on every pass after that.
    ///
    /// Marked as said whether or not anything went out. The model declining, or
    /// the room having gone quiet, both mean this transition has had its chance;
    /// holding the debt open would spend a call on every sync until the room
    /// happened to be busy, and would eventually deliver a goodbye for a burn
    /// that ended hours earlier.
    func announceEndedBurn(
        room: ChatRoom,
        account: AccountProfile,
        policy: RoomPolicy,
        style: ResponseStyle,
        state: BurningState?,
        at now: Date
    ) async -> AgentAction? {
        guard policy.burning.isEnabled,
              policy.announcements.announces(.burningEnded),
              let store = burningStore,
              let state
        else {
            return nil
        }
        let announcedAt = try? await store.announcedAt(
            for: room.id,
            accountFingerprint: account.fingerprint
        )
        guard state.hasJustEnded(at: now, announcedAt: announcedAt ?? nil) else { return nil }

        try? await store.markAnnounced(at: now, for: room.id, accountFingerprint: account.fingerprint)
        let action = await announce(
            .burningEnded,
            room: room,
            account: account,
            policy: policy,
            style: style,
            at: now
        )
        if let action { try? await actionLog.record(action) }
        return action
    }

    /// The line that explains why the room is about to get talkative.
    ///
    /// It matters most exactly where the feature is least visible: one measured
    /// setup has rooms at 10%, and one of those jumping to 90% with nothing said
    /// is a change of character with no cause on screen.
    func announceStartedBurn(
        room: ChatRoom,
        account: AccountProfile,
        policy: RoomPolicy,
        style: ResponseStyle,
        at now: Date
    ) async -> AgentAction? {
        let action = await announce(
            .burningStarted,
            room: room,
            account: account,
            policy: policy,
            style: style,
            at: now
        )
        if let action { try? await actionLog.record(action) }
        return action
    }
}

extension DraftRepliesForChangedRooms {
    /// The line said when 답변 활성화 시간 opened or closed, on the first pass that
    /// notices the boundary was crossed.
    ///
    /// Nothing anticipates a closing, and nothing needs to. The schedule is not
    /// guessed at — the user typed it — so the app compares the phase now against
    /// the phase last time and knows. An earlier design waited for a notice
    /// window before the hours shut, which was solving a problem that does not
    /// exist.
    ///
    /// The closing line goes out *after* the hours have closed, which is the one
    /// place this feature is allowed past that gate. Blocking the message that
    /// says the hours ended because the hours ended leaves the room told nothing
    /// at all, and the user asked for exactly this line at exactly this moment.
    ///
    /// The phase is recorded whether or not anything is said. It is a record of
    /// where the room was, not of what was announced; skipping the write when a
    /// room is quiet would leave the boundary uncrossed and fire the greeting at
    /// some unrelated hour days later.
    func announceHoursChange(
        room: ChatRoom,
        account: AccountProfile,
        policy: RoomPolicy,
        style: ResponseStyle,
        at now: Date
    ) async -> AgentAction? {
        guard let store = burningStore, policy.activeHours.isLimited else { return nil }
        let isOpen = policy.activeHours.allows(now, calendar: .current)
        let was = try? await store.hoursWereOpen(
            for: room.id,
            accountFingerprint: account.fingerprint
        )
        try? await store.recordHoursOpen(
            isOpen,
            for: room.id,
            accountFingerprint: account.fingerprint
        )

        // A room seen for the first time has not crossed anything. Reading a
        // missing phase as closed would greet every room once, on the first sync
        // after this shipped.
        guard let previous = was ?? nil, previous != isOpen else { return nil }

        let action = await announce(
            isOpen ? .activeHoursOpened : .activeHoursClosed,
            room: room,
            account: account,
            policy: policy,
            style: style,
            at: now
        )
        if let action { try? await actionLog.record(action) }
        return action
    }
}

extension StateAnnouncement {
    /// What the activity row calls this, so a person reading the timeline can
    /// tell a hello from a goodbye without opening it.
    var recordLabel: String {
        switch self {
        case .burningStarted: "집중 시작"
        case .burningEnded: "집중 종료"
        case .activeHoursOpened: "답변 시간 시작"
        case .activeHoursClosed: "답변 시간 종료"
        }
    }
}
