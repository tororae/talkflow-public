import Foundation
import TalkFlowDomain

/// The recording half of what `+Drafting` opens with: queue what the model
/// produced, and leave a row in 활동 either way — including for the silence
/// that is worth explaining.
///
/// Apart from the asking because a call that failed and a call that came back
/// empty are recorded by the same code, and because nothing here spends money.
extension DraftRepliesForChangedRooms {
    enum Recording {
        case answered(ReplyDraft)
        case failed(Error)
    }

    /// Queues what the model produced and leaves a row either way.
    func record(
        _ recording: Recording,
        trigger triggerMessageID: String,
        answeredFromID: String?,
        room: ChatRoom,
        account: AccountProfile,
        policy: RoomPolicy,
        window: ConversationWindow.Bounded,
        timeline: ActionTimeline
    ) async -> AgentAction? {
        var timeline = timeline
        let latest = window.messages.last
        // Read off the window rather than the whole fetch: a reply cannot be a
        // response to a message the model never saw, and the two counts on the
        // record would otherwise be able to contradict each other.
        let answered = AnsweredRun.from(window.messages, startingAt: answeredFromID)

        let action: AgentAction
        switch recording {
        case let .answered(reply):
            if let text = reply.usableText, policy.deliveryMode.deliversAutomatically {
                try? await sendStore?.enqueue(
                    PendingSend(
                        accountFingerprint: account.fingerprint,
                        chatRoomID: room.id,
                        chatRoomName: room.displayName,
                        triggerMessageID: triggerMessageID,
                        triggerSenderID: window.messages.first { $0.id == triggerMessageID }?.sender.id,
                        text: text,
                        eligibleAt: Date().addingTimeInterval(settlingDelay)
                    )
                )
                timeline.stamp(
                    .queued,
                    note: settlingDelay > 0 ? "안정화 \(Int(settlingDelay.rounded()))초 뒤 전송 가능" : nil
                )
            }
            action = AgentAction(
                accountFingerprint: account.fingerprint,
                chatRoomID: room.id,
                chatRoomName: room.displayName,
                kind: reply.usableText == nil ? .held : .drafted,
                triggerMessageID: triggerMessageID,
                triggerSenderID: latest?.sender.id,
                triggerText: latest?.body,
                triggerSenderName: latest?.sender.displayName,
                answeredRun: answered,
                replyMode: reply.mode,
                confidence: reply.confidence,
                replyText: reply.usableText,
                detail: Self.detail(for: reply, policy: policy),
                contextMessageCount: window.messages.count,
                timeline: timeline
            )
        case let .failed(error):
            action = AgentAction(
                accountFingerprint: account.fingerprint,
                chatRoomID: room.id,
                chatRoomName: room.displayName,
                kind: .failed,
                triggerMessageID: triggerMessageID,
                triggerSenderID: latest?.sender.id,
                triggerText: latest?.body,
                triggerSenderName: latest?.sender.displayName,
                answeredRun: answered,
                detail: error.localizedDescription,
                contextMessageCount: window.messages.count,
                timeline: timeline
            )
        }

        try? await actionLog.record(action)
        return action
    }

    /// Every other sentence in this field is one the app wrote, so the reason
    /// says whose words follow it. Model text dropped in unlabelled would be
    /// indistinguishable from a rule TalkFlow applied, and this field already
    /// carries those — a cooldown and a judgement are both 보류 in the 결과 column.
    ///
    /// The label stays short because the timeline shows this line in a
    /// single-line cell, which is where the fixed sentence failed: a row that
    /// spends its width restating what the 결과 column said is the row this
    /// change exists to replace.
    private static func detail(for reply: ReplyDraft, policy: RoomPolicy) -> String {
        base(for: reply, policy: policy) + lookupSuffix(reply)
    }

    private static func base(for reply: ReplyDraft, policy: RoomPolicy) -> String {
        guard reply.usableText != nil else {
            guard let reason = reply.usableDeclineReason else { return "AI가 답하지 않기로 판단했습니다." }
            return "AI 판단: \(reason)"
        }
        return policy.deliveryMode.deliversAutomatically
            ? "초안을 만들어 전송 대기열에 넣었습니다."
            : "초안을 만들었습니다. 전송 방식: \(policy.deliveryMode.title)"
    }

    /// Says what the reply reached for — a web search, a link read, or both —
    /// when it reached for anything. Appended rather than folded into each
    /// sentence because it is true of a 보류 and a 초안 alike, so both branches
    /// above would otherwise have to carry it.
    private static func lookupSuffix(_ reply: ReplyDraft) -> String {
        var parts: [String] = []
        if reply.webSearchCount > 0 { parts.append("웹 검색 \(reply.webSearchCount)회") }
        if reply.linksReadCount > 0 { parts.append("링크 \(reply.linksReadCount)개 읽음") }
        guard !parts.isEmpty else { return "" }
        return " " + parts.joined(separator: " · ") + "."
    }

    /// Routine silence is not worth a timeline entry. A cooldown or a person
    /// beating TalkFlow to the answer is, because the user would otherwise
    /// wonder why an enabled room said nothing.
    ///
    /// Being outside the room's active hours is the routine kind, and the most
    /// prolific: it holds every message for as many hours as the window excludes,
    /// so an overnight group room alone could push a night's worth of identical
    /// rows past the history the screen shows. The user set those hours, and the
    /// room's own settings say so — the timeline keeps room for the holds nobody
    /// asked for.
    ///
    /// A room accumulating for its next batch is the same kind of expected
    /// silence, at the same volume: one row per message for the whole interval,
    /// saying only that the room is doing what it was set to do.
    func recordHoldIfNotable(
        _ reason: ReplyHoldReason,
        room: ChatRoom,
        account: AccountProfile,
        latest: ChatMessage,
        timeline: ActionTimeline
    ) async -> AgentAction? {
        switch reason {
        case .cooldown:
            break
        default:
            return nil
        }

        let action = AgentAction(
            accountFingerprint: account.fingerprint,
            chatRoomID: room.id,
            chatRoomName: room.displayName,
            kind: .held,
            triggerMessageID: latest.id,
            triggerSenderID: latest.sender.id,
            triggerText: latest.body,
            triggerSenderName: latest.sender.displayName,
            detail: reason.explanation,
            timeline: timeline
        )
        try? await actionLog.record(action)
        return action
    }
}
