import Testing
import TalkFlowDomain

private let base = RoomPolicy(accountFingerprint: "fp", chatRoomID: "r", responseMode: .off)

@Test
func fullPresetOpensResponseDeliveryAndEveryPermission() {
    let p = RoomPreset.apply("풀", to: base)
    #expect(p?.responseMode == .automatic)
    #expect(p?.deliveryMode == .always)
    #expect(p?.readsPhotos == true)
    #expect(p?.webSearch == true)
    #expect(p?.readsLinks == true)
    #expect(p?.remembersConversation == true)
    #expect(p?.remembersPeople == true)
    // 별칭 풀오토도 같은 결과.
    #expect(RoomPreset.apply("풀오토", to: base) == p)
}

@Test
func permissionPresetTouchesOnlyThePermissionsNotResponse() {
    let p = RoomPreset.apply("권한", to: base)
    #expect(p?.responseMode == .off)        // 응답·전송은 건드리지 않는다
    #expect(p?.readsPhotos == true)
    #expect(p?.webSearch == true)
    #expect(p?.remembersPeople == true)
}

@Test
func quietPresetSetsMentionOnlyAndNoOpener() {
    var on = base
    on.responseMode = .automatic
    on.conversationOpener = .delivers
    let p = RoomPreset.apply("조용히", to: on)
    #expect(p?.responseMode == .mentionOnly)
    #expect(p?.conversationOpener == .off)
}

@Test
func anUnknownPresetIsNilAndHasNoSummary() {
    #expect(RoomPreset.apply("없는거", to: base) == nil)
    #expect(RoomPreset.summary("없는거") == nil)
    #expect(RoomPreset.summary("풀") != nil)
    #expect(RoomPreset.all.map(\.name) == ["풀", "권한", "조용히"])
}
