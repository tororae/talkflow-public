import Foundation
import TalkFlowDomain

/// The half that spends money and writes records, split from the deciding half
/// the same way the reply pipeline is: everything here has already been decided
/// worth doing, and the two fail differently.
extension OpenConversationsInQuietRooms {
    func open(
        room: ChatRoom,
        policy: RoomPolicy,
        account: AccountProfile,
        messages: [ChatMessage],
        style: ResponseStyle,
        now: Date
    ) async -> AgentAction? {
        let window = ConversationWindow.bounded(messages)
        // The key an opener is resolved by. Not the room's newest message, even
        // though that is what the silence is measured from: a reply draft may
        // already be waiting on that same message, and two rows under one trigger
        // id are one row as far as "has this been dealt with" is concerned.
        let key = ConversationOpenerKey.make()

        let request = ReplyDraftRequest(
            room: room,
            intent: .openConversation,
            // The model is told nothing was asked, so the trigger only satisfies
            // the shared request shape. Photos are left out for the same reason
            // they are elsewhere unless a room asks — and no room asked for them
            // to be spent on a message nobody is waiting for.
            trigger: .spontaneous,
            triggerMessageID: key,
            recentMessages: window.messages,
            style: policy.responseStyle(global: style),
            // 답변 조건 is about what deserves an answer, and nothing here is being
            // answered. Handing "잡담엔 끼지 마" to a prompt that opens a subject
            // would be reading one setting as another; what governs this path is
            // 먼저 말 걸기 and its own cadence.
            answeringCondition: .empty,
            // The room's own 요약, so an opener has somewhere to find a subject once
            // the thread has run dry. Nil unless the room 대화를 기억 and a usable
            // summary exists, which leaves a room without one opening from the
            // conversation alone.
            conversationSummary: await summaryText(for: room, account: account, policy: policy),
            omittedMessageCount: window.omittedCount,
            openerHint: policy.openerPromptHint,
            // A repeat when TalkFlow itself said the last thing here — the run of
            // openers nobody has answered. The prompt reads this together with the
            // room's 재시도 주제 to decide whether to press the same subject or open a
            // new one; a first opener, where the other side spoke last, is neither.
            isRepeatOpener: messages.last?.isFromMe == true,
            openerRepeatTopic: policy.openerRepeatTopic
        )

        // No detection stage: nothing arrived. This path exists precisely because
        // the room said nothing, so its clock starts at the sweep's own decision
        // and the only span worth showing is the model's.
        var timeline = ActionTimeline().stamping(.judged, at: now)

        let action: AgentAction
        do {
            timeline.stamp(.modelRequested)
            let draft = try await generator.generateReply(request)
            timeline.stamp(.modelAnswered)
            if let text = draft.usableText, policy.openerDeliversAutomatically {
                try? await sendStore?.enqueue(
                    PendingSend(
                        accountFingerprint: account.fingerprint,
                        chatRoomID: room.id,
                        chatRoomName: room.displayName,
                        triggerMessageID: key,
                        // Carried so the gate can check the silence again at the
                        // last moment. The room speaking between here and there
                        // takes away the reason this was allowed at all.
                        opensConversationAfterMessageID: messages.last?.id,
                        text: text,
                        eligibleAt: now.addingTimeInterval(settlingDelay)
                    )
                )
                timeline.stamp(.queued)
            }
            action = record(
                kind: .opened,
                room: room,
                account: account,
                key: key,
                replyText: draft.usableText,
                confidence: draft.confidence,
                detail: detail(for: draft, policy: policy),
                contextMessageCount: window.messages.count,
                timeline: timeline,
                now: now
            )
        } catch {
            action = record(
                kind: .failed,
                room: room,
                account: account,
                key: key,
                replyText: nil,
                confidence: nil,
                detail: error.localizedDescription,
                contextMessageCount: window.messages.count,
                timeline: timeline.stamping(.failed, note: error.localizedDescription),
                now: now
            )
        }

        try? await actionLog.record(action)
        return action
    }

    /// No trigger text, no sender, no answered run. This answered nothing, and a
    /// record that shows the room's last message beside it would read as a reply
    /// to that message — which is the one thing the timeline has to keep straight
    /// about this feature.
    ///
    /// The context count is not decoration: it is what marks a row as having cost
    /// a model call, and the next cycle starts from the newest row that did. An
    /// opener recorded without it would be asked for again on the next poll.
    private func record(
        kind: AgentAction.Kind,
        room: ChatRoom,
        account: AccountProfile,
        key: String,
        replyText: String?,
        confidence: ReplyDraft.Confidence?,
        detail: String,
        contextMessageCount: Int,
        timeline: ActionTimeline,
        now: Date
    ) -> AgentAction {
        AgentAction(
            accountFingerprint: account.fingerprint,
            chatRoomID: room.id,
            chatRoomName: room.displayName,
            kind: kind,
            triggerMessageID: key,
            confidence: confidence,
            replyText: replyText,
            detail: detail,
            contextMessageCount: contextMessageCount,
            timeline: timeline,
            // The sweep's own instant rather than a fresh one: this row is what
            // the next cycle is measured from, and reading a different clock than
            // the gate did would put the two a few milliseconds out of step.
            createdAt: now
        )
    }

    /// Says which of the two consents produced this row. "초안을 만들었습니다" would
    /// be true of a reply as well, and the difference between a message waiting
    /// for the user and a message already gone is the difference this setting is
    /// careful about everywhere else.
    private func detail(for draft: ReplyDraft, policy: RoomPolicy) -> String {
        guard draft.usableText != nil else {
            guard let reason = draft.usableDeclineReason else { return "AI가 먼저 말 걸지 않기로 판단했습니다." }
            return "AI 판단: \(reason)"
        }
        return policy.openerDeliversAutomatically
            ? "먼저 말 걸 내용을 만들어 전송 대기열에 넣었습니다."
            : "먼저 말 걸 내용을 만들었습니다. 보내려면 검토가 필요합니다."
    }

    /// The room's summary as plain text, or nil — the reply path's own gate,
    /// mirrored: only when the room 대화를 기억 and the stored summary is usable. A
    /// summary the refresher has not written yet, or a room that keeps none, both
    /// come back nil, and the opener draws on the conversation alone.
    private func summaryText(for room: ChatRoom, account: AccountProfile, policy: RoomPolicy) async -> String? {
        guard policy.remembersConversation, let summaryStore else { return nil }
        let stored = try? await summaryStore.summary(for: room, accountFingerprint: account.fingerprint)
        guard let stored, stored.isUsable else { return nil }
        return stored.text
    }
}
