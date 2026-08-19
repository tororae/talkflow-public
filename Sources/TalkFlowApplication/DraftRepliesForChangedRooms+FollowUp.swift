import Foundation
import TalkFlowDomain

/// When a reply waits for the rest of what somebody is saying.
///
/// The decision is the model's and nobody else's. It reads the conversation to
/// write the answer, so it is asked in the same breath whether the person is
/// finished — `ReplyDraft.expectsMore` — and only that answer makes a reply wait.
///
/// Two of the app's own guesses used to stand here instead. One looked for
/// Korean connectives and messages typed close together, and paused before the
/// model had said anything. The other lived at the far end of the pipeline and
/// threw away any finished draft whose subject had spoken again — 113 drafts in
/// three days, and it never converged, because redrafting took eight seconds and
/// the same person could speak inside that too.
///
/// What is left is bounded by construction: at most `FollowUpWait.maximumRounds`
/// calls, and the last answer goes out whatever the flag says.
extension DraftRepliesForChangedRooms {
    func draftAllowingFollowUp(
        trigger: ReplyTrigger,
        triggerMessageID: String,
        answeredFromID: String?,
        room: ChatRoom,
        account: AccountProfile,
        policy: RoomPolicy,
        messages: [ChatMessage],
        style: ResponseStyle,
        globalStyle: ResponseStyle,
        condition: AnsweringCondition,
        searchStage: SearchStage,
        timeline: ActionTimeline
    ) async -> AgentAction? {
        var timeline = timeline
        var messages = messages
        var trigger = trigger
        var triggerMessageID = triggerMessageID
        var round = 0

        while true {
            round += 1
            let window = ConversationWindow.bounded(messages)
            let attempt = await ask(
                trigger: trigger,
                triggerMessageID: triggerMessageID,
                room: room,
                account: account,
                policy: policy,
                window: window,
                style: style,
                condition: condition,
                searchStage: searchStage,
                timeline: timeline
            )
            timeline = attempt.timeline

            let reply: ReplyDraft
            switch attempt.outcome {
            case let .failure(error):
                return await record(
                    .failed(error),
                    trigger: triggerMessageID,
                    answeredFromID: answeredFromID,
                    room: room,
                    account: account,
                    policy: policy,
                    window: window,
                    timeline: timeline
                )
            case let .success(answered):
                reply = answered
            }

            func deliver() async -> AgentAction? {
                await record(
                    .answered(reply),
                    trigger: triggerMessageID,
                    answeredFromID: answeredFromID,
                    room: room,
                    account: account,
                    policy: policy,
                    window: window,
                    timeline: timeline
                )
            }

            guard FollowUpWait.mayWaitAgain(round: round, reply: reply) else {
                return await deliver()
            }

            await pause(followUpDelay)
            timeline.stamp(.followUpWaited, note: FollowUpWait.note(round: round))

            // Read again under the rules the first reading passed, not just for
            // new text. Ten seconds is long enough for the user to have answered
            // by hand, for the room to have left its active hours, or for the
            // room's own cadence to have moved — and an answer in hand is not a
            // licence to skip the checks that decided it was wanted.
            //
            // The anchor is pinned to what the first reading set out to answer.
            // A wait adds to the end of a run rather than starting a new one, and
            // 끼어들기 확률 is drawn from that message: re-rolling it here would
            // make a 40% room drop four in ten answers it had already accepted.
            guard let settled = await judge(
                room: room,
                account: account,
                policy: policy,
                style: globalStyle,
                answering: answeredFromID
            ) else {
                // The room could not be read. That says nothing about the answer
                // already in hand, and dropping it would waste a call the user
                // is waiting on.
                return await deliver()
            }

            switch settled.evaluation {
            case let .hold(reason):
                // The rules changed their mind in those ten seconds — most often
                // because the user answered for themselves. Sending now would be
                // the second reply to one message.
                guard let latest = settled.messages.last else { return nil }
                return await recordHoldIfNotable(
                    reason,
                    room: room,
                    account: account,
                    latest: latest,
                    timeline: timeline
                )
            case let .ask(nextTrigger, nextTriggerMessageID):
                // Nobody said anything. The wait bought nothing and asking again
                // would spend a second call to be told the same thing.
                guard nextTriggerMessageID != triggerMessageID else { return await deliver() }
                messages = settled.messages
                trigger = nextTrigger
                triggerMessageID = nextTriggerMessageID
            }
        }
    }
}
