import Foundation
import Testing
@testable import TalkFlowDomain

// MARK: - 뒷말 대기

/// Nothing waits unless the model asked it to. This is the common answer, and
/// it is the one the whole change is for: a finished sentence gets a reply that
/// goes out now.
@Test
func aReplyTheModelCalledFinishedDoesNotWait() {
    #expect(!FollowUpWait.mayWaitAgain(round: 1, reply: pacingDraft(expectsMore: false)))
}

/// The one thing that makes a reply wait.
@Test
func theModelSayingMoreIsComingIsWhatBuysAWait() {
    #expect(FollowUpWait.mayWaitAgain(round: 1, reply: pacingDraft(expectsMore: true)))
}

/// It can ask again — somebody writing a long thought in pieces genuinely needs
/// it — but not forever. On the last round the answer goes out whatever the flag
/// says, so a model that always sets it costs a bounded delay rather than a
/// reply that never arrives.
@Test
func theModelCannotKeepAskingForever() {
    let stillTyping = pacingDraft(expectsMore: true)

    #expect(FollowUpWait.mayWaitAgain(round: FollowUpWait.maximumRounds - 1, reply: stillTyping))
    #expect(!FollowUpWait.mayWaitAgain(round: FollowUpWait.maximumRounds, reply: stillTyping))
}

/// Declining and flagging is what the model actually does with a sentence that
/// stops mid-thought — measured against Codex: 「아 맞다 / 내일 회의 자료 말인데」
/// came back `should_reply: false, expects_more: true`. Reading that as nothing
/// to wait for would file a 보류 against half a sentence and make the rest of the
/// thought wait for a whole detection cycle.
@Test
func decliningBecauseTheyAreStillTalkingStillWaits() {
    let notYet = ReplyDraft(
        shouldReply: false,
        mode: .spontaneous,
        confidence: .high,
        text: nil,
        expectsMore: true
    )

    #expect(FollowUpWait.mayWaitAgain(round: 1, reply: notYet))
}

/// A pass that is not about timing has nothing to wait for. Holding a settled
/// decision not to speak would only delay the next room.
@Test
func aPlainPassDoesNotWait() {
    let declined = ReplyDraft(
        shouldReply: false,
        mode: .directQuestion,
        confidence: .high,
        text: nil
    )

    #expect(!FollowUpWait.mayWaitAgain(round: 1, reply: declined))
}

/// The wait is seconds. A reply that arrives a minute late reads as a bot
/// catching up rather than as somebody talking.
@Test
func theWaitIsMeasuredInSecondsRatherThanMinutes() {
    #expect(FollowUpWait.defaultDelay > 0)
    #expect(FollowUpWait.defaultDelay <= 15)
}

private func pacingDraft(expectsMore: Bool) -> ReplyDraft {
    ReplyDraft(
        shouldReply: true,
        mode: .directQuestion,
        confidence: .high,
        text: "네 좋아요",
        expectsMore: expectsMore
    )
}

// MARK: - Keeping one call bounded

/// A room that accumulates for minutes can hand one call more conversation than
/// a call should carry, so the oldest messages come off the back.
@Test
func aLongAccumulationIsTrimmedFromTheOldestEnd() {
    let messages = (1...10).map {
        pacingMessage(id: "m\($0)", body: String(repeating: "가", count: 100), secondsAgo: 100 - $0)
    }

    let bounded = ConversationWindow.bounded(messages, characterBudget: 350)

    #expect(bounded.messages.map(\.id) == ["m8", "m9", "m10"])
    #expect(bounded.omittedCount == 7)
}

/// The newest message is the one being answered. A budget small enough to
/// exclude it would leave a prompt that answers nothing.
@Test
func theMessageBeingAnsweredSurvivesAnyBudget() {
    let messages = [
        pacingMessage(id: "m1", body: String(repeating: "가", count: 50), secondsAgo: 20),
        pacingMessage(id: "m2", body: String(repeating: "나", count: 500), secondsAgo: 10)
    ]

    let bounded = ConversationWindow.bounded(messages, characterBudget: 100)

    #expect(bounded.messages.map(\.id) == ["m2"])
    #expect(bounded.omittedCount == 1)
}

@Test
func aConversationInsideBothLimitsIsLeftAlone() {
    let messages = (1...5).map { pacingMessage(id: "m\($0)", body: "짧은 메시지", secondsAgo: 10 - $0) }

    let bounded = ConversationWindow.bounded(messages)

    #expect(bounded.messages.map(\.id) == messages.map(\.id))
    #expect(bounded.omittedCount == 0)
}

/// A prompt that hides its own truncation reads as a whole conversation, and the
/// model answers the missing beginning as though it had seen it.
@Test
func aTrimmedPromptSaysHowMuchItIsMissing() {
    let request = ReplyDraftRequest(
        room: ChatRoom(id: "room", displayName: "프로젝트 팀", kind: .group),
        trigger: .spontaneous,
        triggerMessageID: "m2",
        recentMessages: [pacingMessage(id: "m2", body: "그래서 어떻게 할까요?", secondsAgo: 5)],
        style: ResponseStyle(),
        answeringCondition: .empty,
        omittedMessageCount: 12
    )

    let prompt = ReplyPromptBuilder().prompt(for: request)

    #expect(prompt.contains("앞부분 12개 메시지"))
    #expect(!ReplyPromptBuilder().prompt(for: sameRequestWithNothingOmitted(request)).contains("생략"))
}

private func sameRequestWithNothingOmitted(_ request: ReplyDraftRequest) -> ReplyDraftRequest {
    ReplyDraftRequest(
        room: request.room,
        trigger: request.trigger,
        triggerMessageID: request.triggerMessageID,
        recentMessages: request.recentMessages,
        style: request.style,
        answeringCondition: request.answeringCondition
    )
}

private func pacingMessage(
    id: String,
    senderID: String = "s1",
    body: String,
    secondsAgo: Int
) -> ChatMessage {
    ChatMessage(
        id: id,
        chatRoomID: "room",
        sender: ChatMember(id: senderID, displayName: "상대"),
        body: body,
        sentAt: Date(timeIntervalSince1970: 1_000_000 - Double(secondsAgo))
    )
}
