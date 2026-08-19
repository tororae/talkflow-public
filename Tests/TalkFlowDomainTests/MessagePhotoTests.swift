import Foundation
import Testing
@testable import TalkFlowDomain

/// Reading photos is the one setting that widens what leaves the Mac, so a room
/// nobody configured has to arrive with it off.
@Test
func aRoomNobodyConfiguredReadsNoPhotos() {
    let policy = RoomPolicy.makeDefault(
        accountFingerprint: "katok-test",
        room: ChatRoom(id: "room-1", displayName: "가족", kind: .direct)
    )

    #expect(policy.readsPhotos == false)
}

/// The context is 30 messages and every one of them could be a photo. Without a
/// cap the price of one reply — upload, image tokens, extraction — has no upper
/// bound.
@Test
func onlyTheNewestFewPhotosRideAlongWithAReply() {
    let messages = (1...6).map { photo(id: "p\($0)") }

    let chosen = MessagePhotoSelection.candidates(in: messages)

    #expect(chosen.count == MessagePhotoSelection.limit)
    #expect(chosen.map(\.id) == ["p4", "p5", "p6"])
}

@Test
func aConversationWithFewerPhotosThanTheCapSendsThemAll() {
    let messages = [text(id: "m1"), photo(id: "p1"), text(id: "m2")]

    #expect(MessagePhotoSelection.candidates(in: messages).map(\.id) == ["p1"])
}

/// Emoticons and system feed notices are also "not text", but there is no
/// picture behind them: asking KakaoTalk for one costs a process launch that
/// returns nothing.
@Test
func onlyPhotoMessagesAreWorthExtracting() {
    let messages = [
        text(id: "m1"),
        ChatMessage(
            id: "m2",
            chatRoomID: "room-1",
            sender: ChatMember(id: "s1", displayName: "지수"),
            body: "",
            sentAt: Date(timeIntervalSince1970: 1_000_000),
            kind: .attachment
        ),
        photo(id: "p1")
    ]

    #expect(MessagePhotoSelection.candidates(in: messages).map(\.id) == ["p1"])
}

@Test
func aConversationWithNoPhotosAsksForNothing() {
    #expect(MessagePhotoSelection.candidates(in: [text(id: "m1"), text(id: "m2")]).isEmpty)
}

// MARK: - Fixtures

private func text(id: String) -> ChatMessage {
    ChatMessage(
        id: id,
        chatRoomID: "room-1",
        sender: ChatMember(id: "s1", displayName: "지수"),
        body: "안녕하세요",
        sentAt: Date(timeIntervalSince1970: 1_000_000)
    )
}

private func photo(id: String) -> ChatMessage {
    ChatMessage(
        id: id,
        chatRoomID: "room-1",
        sender: ChatMember(id: "s1", displayName: "지수"),
        body: "사진",
        sentAt: Date(timeIntervalSince1970: 1_000_000),
        kind: .photo
    )
}
