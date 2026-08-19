import Foundation
import Testing
@testable import TalkFlowDomain

/// Measured 2026-08-10 on one room at one moment: KakaoTalk's window title and
/// the archive listed the same members in different orders. Compared as strings
/// they were two rooms, and a room with its window plainly open was marked 닫힘.
@Test
func aMemberListMatchesWhateverOrderItArrivesIn() {
    let window = "김하늘, 박서준, 이도윤, 정민재, 최은우, 한지호, 서예린, 한결"
    let archive = "이도윤, 최은우, 한결, 한지호, 정민재, 박서준, 서예린, 김하늘"

    #expect(RoomNameKey.of(window) == RoomNameKey.of(archive))
}

/// Two rooms with different members stay two rooms.
@Test
func aDifferentMemberListDoesNotMatch() {
    #expect(RoomNameKey.of("가, 나, 다") != RoomNameKey.of("가, 나, 라"))
}

/// An ordinary name is matched as itself.
@Test
func anOrdinaryNameIsUnchanged() {
    #expect(RoomNameKey.of("봄길 독서모임") == "봄길 독서모임")
    #expect(RoomNameKey.of("  늦반딧불 등산모임 ") == "늦반딧불 등산모임")
}

/// A name that happens to contain a comma is folded the same way on both sides,
/// so it still comes out equal to itself.
@Test
func aNameWithACommaStillEqualsItself() {
    #expect(RoomNameKey.of("안녕, 세계") == RoomNameKey.of("안녕, 세계"))
}

/// The same fold has to reach the window search, not only the screen's marks.
/// Measured 2026-08-10: six sends refused as 「대화창이 닫혀 있어」 while that
/// room's window was open — the direct path compared the AX window title to the
/// archive's name as written, and the members were in a different order. Having
/// failed there, it handed the job to katok, which matches by name too and
/// failed for the same reason.
@Test
func aWindowTitleAndAnArchiveNameForOneRoomFoldTogether() {
    let windowTitle = "김하늘, 박서준, 이도윤, 정민재, 최은우, 한지호, 서예린, 한결"
    let archiveName = "이도윤, 최은우, 한결, 한지호, 정민재, 박서준, 서예린, 김하늘"

    #expect(RoomNameKey.of(windowTitle) == RoomNameKey.of(archiveName))
    // And a different room's window still does not answer to it.
    #expect(RoomNameKey.of(windowTitle) != RoomNameKey.of("김하늘, 박서준, 이도윤"))
}
