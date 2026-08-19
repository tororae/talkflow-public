import Foundation
import Testing
import TalkFlowDomain
@testable import TalkFlowApplication

/// A room that is never called records nothing, on purpose. This is what a user
/// gets instead: the count that tells a wrong setting apart from a quiet room.
@Test
func theReportCountsTheMessagesThatCalledAndNamesTheLastOne() async {
    let inspect = InspectRecentCalls(
        connection: FakeKakaoConnection(
            rooms: [testGroupRoom],
            messagesByRoom: [
                testGroupRoom.id: [
                    testMessage(id: "m1", roomID: testGroupRoom.id, body: "오늘 회의 몇 시죠?"),
                    testMessage(id: "m2", roomID: testGroupRoom.id, body: "달구지톡 이거 봐줘"),
                    testMessage(id: "m3", roomID: testGroupRoom.id, body: "달빛 일정 좀"),
                    testMessage(id: "m4", roomID: testGroupRoom.id, body: "고마워요")
                ]
            ]
        )
    )

    let report = await inspect(
        room: testGroupRoom,
        signs: CallSigns(nickname: "달구지톡", globalKeywords: [], roomKeywords: ["달빛"])
    )

    #expect(report.examinedMessages == 4)
    #expect(report.matchedMessages == 2)
    #expect(report.latest?.sign == "달빛")
    #expect(report.latest?.senderName == "지수")
}

/// The answer that explains a whole day of silence: the words are set, and
/// nobody has said any of them.
@Test
func aRoomNobodyCallsReportsZeroWithoutFailing() async {
    let inspect = InspectRecentCalls(
        connection: FakeKakaoConnection(
            rooms: [testGroupRoom],
            messagesByRoom: [
                testGroupRoom.id: [
                    testMessage(id: "m1", roomID: testGroupRoom.id, body: "오늘 회의 몇 시죠?")
                ]
            ]
        )
    )

    let report = await inspect(room: testGroupRoom, signs: CallSigns(nickname: "달구지톡"))

    #expect(report.examinedMessages == 1)
    #expect(report.matchedMessages == 0)
    #expect(report.latest == nil)
}

/// Writing your own name is not being called, and the engine would never treat
/// it as a trigger either.
@Test
func theAccountsOwnMessagesDoNotCountAsCallingIt() async {
    let inspect = InspectRecentCalls(
        connection: FakeKakaoConnection(
            rooms: [testGroupRoom],
            messagesByRoom: [
                testGroupRoom.id: [
                    testMessage(id: "m1", roomID: testGroupRoom.id, body: "달구지톡입니다", isFromMe: true),
                    testMessage(id: "m2", roomID: testGroupRoom.id, body: "사진", kind: .photo)
                ]
            ]
        )
    )

    let report = await inspect(room: testGroupRoom, signs: CallSigns(nickname: "달구지톡"))

    #expect(report.examinedMessages == 2)
    #expect(report.matchedMessages == 0)
}
