import Testing
@testable import TalkFlowDomain

@Test
func chatMemberUsesStableIdentifierInsteadOfDisplayName() {
    let first = ChatMember(id: "1001", displayName: "민수")
    let second = ChatMember(id: "1002", displayName: "민수")

    #expect(first.id != second.id)
    #expect(first.displayName == second.displayName)
}
