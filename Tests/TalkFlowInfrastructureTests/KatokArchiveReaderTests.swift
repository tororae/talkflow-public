import Foundation
import Testing
import TalkFlowDomain
@testable import TalkFlowInfrastructure

@Test
func archiveReaderFailsClearlyWhenNoSyncHasRunYet() throws {
    let fixture = try KatokArchiveFixture()
    defer { fixture.destroy() }

    #expect(throws: KatokArchiveReader.ReadError.self) {
        _ = try KatokArchiveReader(environment: fixture.environment)
    }
}

@Test
func archiveReaderMapsChatTypesAndSkipsUnknownOnes() throws {
    let fixture = try KatokArchiveFixture()
    defer { fixture.destroy() }
    try fixture.createArchive(
        chats: [
            (id: "room-1", name: "가족", type: "direct"),
            (id: "room-2", name: "프로젝트 팀", type: "group"),
            (id: "room-3", name: "미지원 방", type: "openlink")
        ],
        messages: [
            message(id: "m1", chatID: "room-1", text: "가족", timestamp: "2026-08-01T10:00:00+00:00"),
            message(id: "m2", chatID: "room-2", text: "팀", timestamp: "2026-08-01T10:01:00+00:00"),
            message(id: "m3", chatID: "room-3", text: "미지원", timestamp: "2026-08-01T10:02:00+00:00")
        ]
    )

    let rooms = try KatokArchiveReader(environment: fixture.environment).chatRooms()

    #expect(rooms.count == 2)
    #expect(rooms.first { $0.id == "room-1" }?.kind == .direct)
    #expect(rooms.first { $0.id == "room-2" }?.kind == .group)
    #expect(rooms.contains { $0.id == "room-3" } == false)
}

@Test
func archiveReaderReturnsNewestMessagesInChronologicalOrder() throws {
    let fixture = try KatokArchiveFixture()
    defer { fixture.destroy() }
    try fixture.createArchive(
        chats: [(id: "room-1", name: "가족", type: "direct")],
        messages: [
            message(id: "m1", text: "첫 번째", timestamp: "2026-08-01T10:00:00+00:00"),
            message(id: "m2", text: "두 번째", timestamp: "2026-08-01T10:01:00+00:00"),
            message(id: "m3", text: "세 번째", timestamp: "2026-08-01T10:02:00+00:00")
        ]
    )

    let messages = try KatokArchiveReader(environment: fixture.environment)
        .recentMessages(chatRoomID: "room-1", limit: 2)

    #expect(messages.map(\.id) == ["m2", "m3"])
    #expect(messages.first?.sentAt.timeIntervalSince1970 == 1785578460)
}

@Test
func archiveReaderMarksOwnMessagesAndNonTextMessages() throws {
    let fixture = try KatokArchiveFixture(accountSenderID: "1000")
    defer { fixture.destroy() }
    try fixture.createArchive(
        chats: [(id: "room-1", name: "가족", type: "direct")],
        messages: [
            message(id: "m1", senderID: "2000", text: "안녕", timestamp: "2026-08-01T10:00:00+00:00"),
            message(id: "m2", senderID: "1000", text: "응 안녕", timestamp: "2026-08-01T10:01:00+00:00"),
            message(id: "m3", senderID: "2000", text: "", timestamp: "2026-08-01T10:02:00+00:00", type: "type_2")
        ]
    )

    let messages = try KatokArchiveReader(environment: fixture.environment)
        .recentMessages(chatRoomID: "room-1", limit: 10)

    #expect(messages.map(\.isFromMe) == [false, true, false])
    #expect(messages.map(\.kind) == [.text, .text, .photo])
}

/// A photo and a system feed notice are both "not text", and until they were
/// told apart a photo was indistinguishable from a room-renamed row. Only one of
/// them has a picture behind it: asking KakaoTalk for the other costs a process
/// launch that returns nothing.
@Test
func archiveReaderTellsPhotosApartFromTheOtherNonTextRows() throws {
    let fixture = try KatokArchiveFixture()
    defer { fixture.destroy() }
    try fixture.createArchive(
        chats: [(id: "room-1", name: "가족", type: "direct")],
        messages: [
            message(id: "m1", text: "안녕", timestamp: "2026-08-01T10:00:00+00:00"),
            message(id: "m2", text: "사진", timestamp: "2026-08-01T10:01:00+00:00", type: "type_2"),
            message(
                id: "m3",
                text: #"{"feedType":25}"#,
                timestamp: "2026-08-01T10:02:00+00:00",
                type: "type_0"
            ),
            message(id: "m4", text: "", timestamp: "2026-08-01T10:03:00+00:00", type: "type_12")
        ]
    )

    let messages = try KatokArchiveReader(environment: fixture.environment)
        .recentMessages(chatRoomID: "room-1", limit: 10)

    #expect(messages.map(\.kind) == [.text, .photo, .attachment, .attachment])
}

/// A KakaoTalk 답장 names the message it answers, and that is the one address
/// nobody has to configure and no message can arrive at by coincidence. It is
/// dropped on the floor unless it is read off the row and carried along.
@Test
func archiveReaderCarriesTheMessageAReplyWasAnsweringTo() throws {
    let fixture = try KatokArchiveFixture(accountSenderID: "1000")
    defer { fixture.destroy() }
    try fixture.createArchive(
        chats: [(id: "room-1", name: "가족", type: "direct")],
        messages: [
            message(id: "m1", senderID: "1000", text: "저녁 뭐 먹지", timestamp: "2026-08-01T10:00:00+00:00"),
            message(id: "m2", senderID: "2000", text: "그러게", timestamp: "2026-08-01T10:01:00+00:00"),
            message(
                id: "m3",
                senderID: "2000",
                text: "국수 어때",
                timestamp: "2026-08-01T10:02:00+00:00",
                replyTo: "m1"
            )
        ]
    )

    let messages = try KatokArchiveReader(environment: fixture.environment)
        .recentMessages(chatRoomID: "room-1", limit: 10)

    #expect(messages.map(\.replyToMessageID) == [nil, nil, "m1"])
}

/// An id of "" names no message, so it is not an answer to one — but anything
/// that only checks for nil would take it for one.
@Test
func archiveReaderTreatsABlankReplyIDAsNoReply() throws {
    let fixture = try KatokArchiveFixture()
    defer { fixture.destroy() }
    try fixture.createArchive(
        chats: [(id: "room-1", name: "가족", type: "direct")],
        messages: [
            message(id: "m1", text: "안녕", timestamp: "2026-08-01T10:00:00+00:00", replyTo: "")
        ]
    )

    let messages = try KatokArchiveReader(environment: fixture.environment)
        .recentMessages(chatRoomID: "room-1", limit: 10)

    #expect(messages.first?.replyToMessageID == nil)
}

@Test
func archiveReaderIgnoresOtherChatRooms() throws {
    let fixture = try KatokArchiveFixture()
    defer { fixture.destroy() }
    try fixture.createArchive(
        chats: [
            (id: "room-1", name: "가족", type: "direct"),
            (id: "room-2", name: "친구", type: "direct")
        ],
        messages: [
            message(id: "m1", chatID: "room-1", text: "가족 메시지", timestamp: "2026-08-01T10:00:00+00:00"),
            message(id: "m2", chatID: "room-2", text: "친구 메시지", timestamp: "2026-08-01T10:01:00+00:00")
        ]
    )

    let reader = try KatokArchiveReader(environment: fixture.environment)

    #expect(try reader.recentMessages(chatRoomID: "room-1", limit: 10).map(\.id) == ["m1"])
    #expect(try reader.archiveSummary() == (messages: 2, chatRooms: 2))
}

private func message(
    id: String,
    chatID: String = "room-1",
    senderID: String = "2000",
    nickname: String = "상대",
    text: String,
    timestamp: String,
    type: String = "text",
    replyTo: String? = nil
) -> KatokArchiveFixture.ArchivedMessage {
    KatokArchiveFixture.ArchivedMessage(
        id: id,
        chatID: chatID,
        senderID: senderID,
        nickname: nickname,
        text: text,
        timestamp: timestamp,
        type: type,
        replyTo: replyTo
    )
}
