import Foundation
import Testing
import TalkFlowDomain
@testable import TalkFlowInfrastructure

/// The name has to come out of the archive, because nobody types their own
/// KakaoTalk name into a settings screen and the app has no other way to know
/// what other people call this account.
@Test
func archiveReaderReadsTheAccountsOwnNameOffTheMessagesItSent() throws {
    let fixture = try KatokArchiveFixture(accountSenderID: "1000")
    defer { fixture.destroy() }
    try fixture.createArchive(
        chats: [(id: "room-1", name: "가족", type: "direct")],
        messages: [
            message(id: "m1", senderID: "2000", nickname: "지수", text: "안녕", timestamp: "2026-08-01T10:00:00+00:00"),
            message(id: "m2", senderID: "1000", nickname: "달구지톡", text: "응 안녕", timestamp: "2026-08-01T10:01:00+00:00")
        ]
    )

    #expect(try KatokArchiveReader(environment: fixture.environment).accountNickname() == "달구지톡")
}

/// Renaming yourself in KakaoTalk leaves every older message under the old name,
/// so the newest one is the one people are typing today.
@Test
func archiveReaderPrefersTheNewestNameWhenTheAccountWasRenamed() throws {
    let fixture = try KatokArchiveFixture(accountSenderID: "1000")
    defer { fixture.destroy() }
    try fixture.createArchive(
        chats: [(id: "room-1", name: "가족", type: "direct")],
        messages: [
            message(id: "m1", senderID: "1000", nickname: "예전이름", text: "옛날", timestamp: "2026-07-01T10:00:00+00:00"),
            message(id: "m2", senderID: "1000", nickname: "달구지톡", text: "요즘", timestamp: "2026-08-01T10:00:00+00:00")
        ]
    )

    #expect(try KatokArchiveReader(environment: fixture.environment).accountNickname() == "달구지톡")
}

/// A brand-new sign-in has written nothing, so there is no message to read a
/// name off. Nil has to stay nil: borrowing the nickname of whoever did write
/// would have the account answer to a stranger's name.
@Test
func archiveReaderReportsNoNameForAnAccountThatHasNeverWritten() throws {
    let fixture = try KatokArchiveFixture(accountSenderID: "1000")
    defer { fixture.destroy() }
    try fixture.createArchive(
        chats: [(id: "room-1", name: "가족", type: "direct")],
        messages: [
            message(id: "m1", senderID: "2000", nickname: "지수", text: "안녕", timestamp: "2026-08-01T10:00:00+00:00")
        ]
    )

    let reader = try KatokArchiveReader(environment: fixture.environment)

    #expect(reader.accountNickname() == nil)
    #expect(reader.accountNickname(chatRoomID: "room-1") == nil)
}

/// katok writes an empty nickname for some rows. An empty name would match every
/// message ever sent, so it is no name at all.
@Test
func archiveReaderTreatsABlankNameAsNoName() throws {
    let fixture = try KatokArchiveFixture(accountSenderID: "1000")
    defer { fixture.destroy() }
    try fixture.createArchive(
        chats: [(id: "room-1", name: "가족", type: "direct")],
        messages: [
            message(id: "m1", senderID: "1000", nickname: "  ", text: "응", timestamp: "2026-08-01T10:00:00+00:00")
        ]
    )

    #expect(try KatokArchiveReader(environment: fixture.environment).accountNickname() == nil)
}

/// One account wears a different name in each room — open chats are where people
/// do it on purpose. Read across all rooms, the newest name anywhere wins, and
/// the room where the user renamed themselves stops answering to its own name.
@Test
func archiveReaderReadsTheNameTheAccountUsesInEachRoom() throws {
    let fixture = try KatokArchiveFixture(accountSenderID: "1000")
    defer { fixture.destroy() }
    try fixture.createArchive(
        chats: [
            (id: "room-1", name: "가족", type: "direct"),
            (id: "room-2", name: "주말 산책", type: "group")
        ],
        messages: [
            message(id: "m1", chatID: "room-1", senderID: "1000", nickname: "달구지톡", text: "응", timestamp: "2026-08-01T10:00:00+00:00"),
            message(id: "m2", chatID: "room-2", senderID: "1000", nickname: "모임총무", text: "출발", timestamp: "2026-08-01T11:00:00+00:00")
        ]
    )

    let reader = try KatokArchiveReader(environment: fixture.environment)

    #expect(reader.accountNickname(chatRoomID: "room-1") == "달구지톡")
    #expect(reader.accountNickname(chatRoomID: "room-2") == "모임총무")
    #expect(reader.accountNickname() == "모임총무")
}

/// Renaming yourself inside one room leaves that room's older messages under the
/// old name, exactly as renaming the account does.
@Test
func archiveReaderPrefersTheNewestNameTheAccountUsedInThatRoom() throws {
    let fixture = try KatokArchiveFixture(accountSenderID: "1000")
    defer { fixture.destroy() }
    try fixture.createArchive(
        chats: [
            (id: "room-1", name: "주말 산책", type: "group"),
            (id: "room-2", name: "가족", type: "direct")
        ],
        messages: [
            message(id: "m1", chatID: "room-1", senderID: "1000", nickname: "예전총무", text: "옛날", timestamp: "2026-07-01T10:00:00+00:00"),
            message(id: "m2", chatID: "room-1", senderID: "1000", nickname: "모임총무", text: "요즘", timestamp: "2026-08-01T10:00:00+00:00"),
            message(id: "m3", chatID: "room-2", senderID: "1000", nickname: "달구지톡", text: "가장 최근", timestamp: "2026-08-02T10:00:00+00:00")
        ]
    )

    #expect(
        try KatokArchiveReader(environment: fixture.environment)
            .accountNickname(chatRoomID: "room-1") == "모임총무"
    )
}

/// A room the account has never spoken in has no name to read, and it is still
/// the same person: the name they use everywhere else is what that room would
/// call them.
@Test
func archiveReaderFallsBackToTheAllRoomsNameWhereTheAccountHasNotWritten() throws {
    let fixture = try KatokArchiveFixture(accountSenderID: "1000")
    defer { fixture.destroy() }
    try fixture.createArchive(
        chats: [
            (id: "room-1", name: "가족", type: "direct"),
            (id: "room-2", name: "주말 산책", type: "group")
        ],
        messages: [
            message(id: "m1", chatID: "room-1", senderID: "1000", nickname: "달구지톡", text: "응", timestamp: "2026-08-01T10:00:00+00:00"),
            message(id: "m2", chatID: "room-2", senderID: "2000", nickname: "지수", text: "다들 나와요", timestamp: "2026-08-01T11:00:00+00:00")
        ]
    )

    #expect(
        try KatokArchiveReader(environment: fixture.environment)
            .accountNickname(chatRoomID: "room-2") == "달구지톡"
    )
}

/// A blank name in a room is not a name the room uses, so it falls back rather
/// than leaving that room unable to recognise a call.
@Test
func archiveReaderFallsBackWhenTheRoomsOwnNameIsBlank() throws {
    let fixture = try KatokArchiveFixture(accountSenderID: "1000")
    defer { fixture.destroy() }
    try fixture.createArchive(
        chats: [
            (id: "room-1", name: "가족", type: "direct"),
            (id: "room-2", name: "주말 산책", type: "group")
        ],
        messages: [
            message(id: "m1", chatID: "room-2", senderID: "1000", nickname: "  ", text: "네", timestamp: "2026-08-01T09:00:00+00:00"),
            message(id: "m2", chatID: "room-1", senderID: "1000", nickname: "달구지톡", text: "응", timestamp: "2026-08-01T10:00:00+00:00")
        ]
    )

    #expect(
        try KatokArchiveReader(environment: fixture.environment)
            .accountNickname(chatRoomID: "room-2") == "달구지톡"
    )
}

/// The connection is what the rest of the app asks, and it has to ask per room:
/// a room-scoped answer that never leaves the reader changes nothing.
@Test
func theConnectionAnswersWithTheNameTheAccountUsesInThatRoom() async throws {
    let fixture = try KatokArchiveFixture(accountSenderID: "1000")
    defer { fixture.destroy() }
    try fixture.createArchive(
        chats: [
            (id: "room-1", name: "가족", type: "direct"),
            (id: "room-2", name: "주말 산책", type: "group")
        ],
        messages: [
            message(id: "m1", chatID: "room-1", senderID: "1000", nickname: "달구지톡", text: "응", timestamp: "2026-08-01T10:00:00+00:00"),
            message(id: "m2", chatID: "room-2", senderID: "1000", nickname: "모임총무", text: "출발", timestamp: "2026-08-01T11:00:00+00:00")
        ]
    )

    // No executable: reading a name never launches katok, and a test that could
    // launch it would be a test that hangs.
    let connection = KatokConnection(executableURL: nil, environment: fixture.environment)
    let room = ChatRoom(id: "room-1", displayName: "가족", kind: .direct)

    #expect(await connection.accountNickname(in: room) == "달구지톡")
}

/// A connector that cannot tell rooms apart says nothing rather than repeating
/// the account-wide name, so the caller can tell "no room answer" from one.
@Test
func aConnectionWithoutPerRoomNamesAnswersWithNothing() async {
    let room = ChatRoom(id: "room-1", displayName: "가족", kind: .direct)

    #expect(await PreviewKakaoConnection().accountNickname(in: room) == nil)
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

// MARK: - 카카오톡이 아직 보여주는 방

/// Measured 2026-08-10: with six chat windows open, `--list-rooms` returned 58
/// rows that were all the same name — the message list inside the frontmost
/// window rather than the chat list. Believed, it would have marked every room
/// but that one as no longer joined.
@Test
func aChatListThatRepeatsItselfIsNotAChatList() {
    let repeated = Array(repeating: "hangyeol", count: 58)

    #expect(KatokConnection.trustworthyRoomNames(rooms: repeated).isEmpty)
}

/// One row per chat is what a chat list looks like.
@Test
func aChatListWithOneRowPerRoomIsBelieved() {
    let rooms = ["봄길 독서모임", "달빛 스튜디오", "hangyeol"]

    #expect(KatokConnection.trustworthyRoomNames(rooms: rooms) == Set(rooms))
}

/// Nothing on screen means nothing is known, not that every room is gone.
@Test
func anEmptyListSaysNothingRatherThanEverything() {
    #expect(KatokConnection.trustworthyRoomNames(rooms: []).isEmpty)
}
