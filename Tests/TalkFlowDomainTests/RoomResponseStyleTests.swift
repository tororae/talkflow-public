import Foundation
import Testing
@testable import TalkFlowDomain

private let account = "katok-style"
private let room = ChatRoom(id: "room-g", displayName: "프로젝트 팀", kind: .group)
private let builder = ReplyPromptBuilder()

private let global = ResponseStyle(
    tone: "정중하고 길게",
    length: .long,
    emojiUse: .frequent,
    assertiveness: .forward,
    responseKeywords: ["한결"]
)

/// A room without an override answers in the global style, and a room with one
/// answers in its own. Off in every room, so nothing changes for a room
/// configured before this existed.
@Test
func aRoomFollowsTheGlobalStyleUntilItIsGivenOneOfItsOwn() {
    let following = policy(style: nil)
    let own = policy(style: ResponseStyle(tone: "짧고 무뚝뚝하게", length: .short, emojiUse: .none))

    #expect(following.responseStyle(global: global) == global)
    #expect(following.usesOwnResponseStyle == false)
    #expect(own.responseStyle(global: global).tone == "짧고 무뚝뚝하게")
    #expect(own.responseStyle(global: global).length == .short)
    #expect(own.responseStyle(global: global).emojiUse == .none)
    #expect(own.usesOwnResponseStyle)
}

/// The keywords are not style. A 말투 override that quietly changed which
/// messages a room answers to would be the worst kind of setting this app has
/// shipped, so they come from the global one whatever the room holds.
@Test
func aRoomsOwnStyleNeverTakesOverWhichMessagesItAnswersTo() {
    let own = policy(style: ResponseStyle(tone: "짧고 무뚝뚝하게", responseKeywords: ["엉뚱한말"]))

    #expect(own.responseStyle(global: global).responseKeywords == ["한결"])
}

/// And the style the room resolved is the style the model is told about. The
/// resolver returning the right value means nothing if the prompt is built from
/// the other one.
@Test
func thePromptIsWrittenInWhicheverStyleTheRoomResolvedTo() {
    let own = policy(style: ResponseStyle(tone: "짧고 무뚝뚝하게", length: .short))
    let following = policy(style: nil)

    let ownPrompt = builder.prompt(for: draft(style: own.responseStyle(global: global)))
    let globalPrompt = builder.prompt(for: draft(style: following.responseStyle(global: global)))

    #expect(ownPrompt.contains("말투: 짧고 무뚝뚝하게"))
    #expect(ownPrompt.contains("길이: 짧게"))
    #expect(globalPrompt.contains("말투: 정중하고 길게"))
    #expect(globalPrompt.contains("길이: 길게"))
}

// MARK: - Fixtures

private func policy(style: ResponseStyle?) -> RoomPolicy {
    RoomPolicy(
        accountFingerprint: account,
        chatRoomID: room.id,
        responseMode: .automatic,
        responseStyleOverride: style
    )
}

private func draft(style: ResponseStyle) -> ReplyDraftRequest {
    ReplyDraftRequest(
        room: room,
        trigger: .spontaneous,
        triggerMessageID: "m1",
        recentMessages: [
            ChatMessage(
                id: "m1",
                chatRoomID: room.id,
                sender: ChatMember(id: "s1", displayName: "상대"),
                body: "다들 점심 뭐 먹어요?",
                sentAt: Date(timeIntervalSince1970: 1_000_000)
            )
        ],
        style: style,
        answeringCondition: .empty
    )
}
