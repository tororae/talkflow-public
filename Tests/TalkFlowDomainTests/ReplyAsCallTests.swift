import Foundation
import Testing
@testable import TalkFlowDomain

private let account = "katok-test"
private let groupRoom = ChatRoom(id: "room-g", displayName: "프로젝트 팀", kind: .group)

private func mentionOnlyPolicy(answersReplies: Bool = true) -> RoomPolicy {
    RoomPolicy(
        accountFingerprint: account,
        chatRoomID: groupRoom.id,
        responseMode: .mentionOnly,
        minimumInterval: 0,
        answersReplies: answersReplies
    )
}

private func message(
    id: String,
    body: String,
    isFromMe: Bool = false,
    replyTo: String? = nil,
    secondsIn: Int
) -> ChatMessage {
    ChatMessage(
        id: id,
        chatRoomID: groupRoom.id,
        sender: ChatMember(id: isFromMe ? "me" : "s1", displayName: isFromMe ? "나" : "지수"),
        body: body,
        sentAt: Date(timeIntervalSince1970: 1_000_000 + Double(secondsIn)),
        isFromMe: isFromMe,
        replyToMessageID: replyTo
    )
}

private func evaluate(_ messages: [ChatMessage], policy: RoomPolicy = mentionOnlyPolicy()) -> ReplyEvaluation {
    ResponsePolicyEngine().evaluate(
        ReplyEvaluationRequest(
            room: groupRoom,
            policy: policy,
            globalResponsesEnabled: true,
            accountVerified: true,
            recentMessages: messages,
            accountNickname: "달구지톡"
        )
    )
}

/// The call that needs no configuring. Somebody picked the account's message out
/// of the room and answered it — there is nothing to guess about who they meant,
/// and no keyword has to have been registered first.
@Test
func aKakaoTalkReplyToOurOwnMessageCountsAsBeingCalled() {
    let conversation = [
        message(id: "m1", body: "내일 두 시에 봐요", isFromMe: true, secondsIn: 0),
        message(id: "m2", body: "그때 자료도 가져올 수 있어?", replyTo: "m1", secondsIn: 30)
    ]

    guard case let .ask(trigger, triggerMessageID) = evaluate(conversation) else {
        Issue.record("답장은 부름으로 읽혀야 합니다")
        return
    }
    #expect(trigger == .mention)
    #expect(triggerMessageID == "m2")
}

/// A reply to somebody else is that somebody else's business. Reading every
/// reply in a group room as a call would make 멘션에만 응답 answer everything.
@Test
func aReplyToSomebodyElsesMessageIsNotACall() {
    let conversation = [
        message(id: "m1", body: "저는 세 시가 좋아요", secondsIn: 0),
        message(id: "m2", body: "저도요", replyTo: "m1", secondsIn: 30)
    ]

    #expect(evaluate(conversation) == .hold(reason: .notAddressed))
}

/// Off for a room that was told to answer names only. The setting exists because
/// a room can want the narrower rule, and a capability that ignored it would be
/// the app overriding a decision the user made.
@Test
func aRoomThatTurnedReplyDetectionOffIgnoresTheReply() {
    let conversation = [
        message(id: "m1", body: "내일 두 시에 봐요", isFromMe: true, secondsIn: 0),
        message(id: "m2", body: "그때 자료도 가져올 수 있어?", replyTo: "m1", secondsIn: 30)
    ]

    #expect(evaluate(conversation, policy: mentionOnlyPolicy(answersReplies: false))
            == .hold(reason: .notAddressed))
}

/// Only what the window holds can be recognised as the thing replied to. A room
/// that answered because it could not see what was quoted would be answering
/// something nobody can read either.
@Test
func aReplyToAMessageOutsideTheWindowReadsAsNoReply() {
    let conversation = [
        message(id: "m2", body: "그때 자료도 가져올 수 있어?", replyTo: "지난주-메시지", secondsIn: 30)
    ]

    #expect(evaluate(conversation) == .hold(reason: .notAddressed))
}

/// An ordinary message is unchanged by any of this: no reply id, no call.
@Test
func aPlainMessageInAMentionOnlyRoomIsStillHeld() {
    #expect(evaluate([message(id: "m1", body: "다들 점심 뭐 먹어요", secondsIn: 0)])
            == .hold(reason: .notAddressed))
}
