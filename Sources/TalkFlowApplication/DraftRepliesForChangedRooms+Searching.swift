import Foundation
import TalkFlowDomain

/// The 웹 검색 two-step: one deciding call, and — only when the model defers —
/// the acknowledgement it wrote for itself followed by a second call that
/// answers with the tool on.
///
/// Kept out of `ask` because it is a *sequence* of calls with a message going
/// out between them, and out of `record` because every branch of it ends in the
/// same recording. Why it is shaped this way is on the method itself.
extension DraftRepliesForChangedRooms {
    /// Answer for a room that reads the web and delivers on its own.
    ///
    /// The first call is the reply judgment with the tool off: it either answers
    /// directly, or — for a genuinely new lookup — defers, naming the topic and
    /// writing its own "잠깐 알아볼게요". Because it is the judgment itself, it sees
    /// its own recent replies and any link text already in the prompt, so it does
    /// not defer for a topic it just answered or a link it can already read.
    ///
    /// If it defers, that acknowledgement goes out and the searched answer follows,
    /// continuing from it in the model's words — usually 「못 찾았어요」 in the room's
    /// own 말투 when the search turned up nothing, since the second call is told not
    /// to decline. The second call failing outright is retried once, because the
    /// deciding call just succeeded so a miss is usually a blip between the beats.
    /// If the retry also comes back with nothing to send, the room stays quiet: the
    /// ack is already out, the conversation is remembered, and a later message can
    /// pick the thread back up — better than a canned line in the wrong voice. No
    /// follow-up wait, no burn roll.
    func answerMaybeSearching(
        trigger: ReplyTrigger,
        triggerMessageID: String,
        answeredFromID: String?,
        room: ChatRoom,
        account: AccountProfile,
        policy: RoomPolicy,
        window: ConversationWindow.Bounded,
        style: ResponseStyle,
        condition: AnsweringCondition,
        timeline: ActionTimeline
    ) async -> AgentAction? {
        let deciding = await ask(
            trigger: trigger,
            triggerMessageID: triggerMessageID,
            room: room,
            account: account,
            policy: policy,
            window: window,
            style: style,
            condition: condition,
            searchStage: .mayDefer,
            timeline: timeline
        )

        let decision: ReplyDraft
        switch deciding.outcome {
        case let .failure(error):
            return await record(
                .failed(error),
                trigger: triggerMessageID,
                answeredFromID: answeredFromID,
                room: room,
                account: account,
                policy: policy,
                window: window,
                timeline: deciding.timeline
            )
        case let .success(reply):
            decision = reply
        }

        // Not deferring — the deciding call is the answer (or a decline). Done.
        guard decision.needsWebSearch,
              let ack = decision.ackMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !ack.isEmpty
        else {
            return await record(
                .answered(decision),
                trigger: triggerMessageID,
                answeredFromID: answeredFromID,
                room: room,
                account: account,
                policy: policy,
                window: window,
                timeline: deciding.timeline
            )
        }

        // Deferring: the model's own acknowledgement goes out first.
        try? await sendStore?.enqueue(
            PendingSend(
                accountFingerprint: account.fingerprint,
                chatRoomID: room.id,
                chatRoomName: room.displayName,
                triggerMessageID: triggerMessageID,
                triggerSenderID: window.messages.first { $0.id == triggerMessageID }?.sender.id,
                text: ack,
                eligibleAt: Date().addingTimeInterval(settlingDelay)
            )
        )

        // The searched answer, continuing from what was just said. One retry on a
        // miss: the deciding call just went through, so a failure here is usually a
        // blip between the two beats rather than a provider that is down.
        var answering = await ask(
            trigger: trigger,
            triggerMessageID: triggerMessageID,
            room: room,
            account: account,
            policy: policy,
            window: window,
            style: style,
            condition: condition,
            searchStage: .answering(ackedWith: ack),
            timeline: deciding.timeline
        )
        if !answering.hasUsableReply {
            answering = await ask(
                trigger: trigger,
                triggerMessageID: triggerMessageID,
                room: room,
                account: account,
                policy: policy,
                window: window,
                style: style,
                condition: condition,
                searchStage: .answering(ackedWith: ack),
                timeline: answering.timeline
            )
        }

        // Whatever the second attempt is, that is what is recorded — no fabricated
        // line. A usable answer is queued; a model that came back empty is 보류; an
        // outright failure is 실패. When there is nothing in the account's own voice
        // to send, the room stays quiet: the ack is out and the conversation is
        // remembered, so a later message can pick the thread back up.
        switch answering.outcome {
        case let .success(reply):
            return await record(
                .answered(reply),
                trigger: triggerMessageID,
                answeredFromID: answeredFromID,
                room: room,
                account: account,
                policy: policy,
                window: window,
                timeline: answering.timeline
            )
        case let .failure(error):
            return await record(
                .failed(error),
                trigger: triggerMessageID,
                answeredFromID: answeredFromID,
                room: room,
                account: account,
                policy: policy,
                window: window,
                timeline: answering.timeline
            )
        }
    }
}
