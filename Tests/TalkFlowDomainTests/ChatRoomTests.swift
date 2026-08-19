import Testing
@testable import TalkFlowDomain

@Test
func chatRoomKeepsStableIdentifierSeparateFromDisplayName() {
    let room = ChatRoom(id: "room-1", displayName: "개발 단체방", kind: .group)

    #expect(room.id == "room-1")
    #expect(room.displayName == "개발 단체방")
    #expect(room.kind == .group)
}
