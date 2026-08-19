import Foundation
import Testing
@testable import TalkFlowDomain

private let start = Date(timeIntervalSince1970: 1_000_000)

private func at(_ seconds: TimeInterval) -> Date {
    start.addingTimeInterval(seconds)
}

/// The whole point of the record: a stage list that reads in the order things
/// happened, whatever order the pipeline got round to stamping them in.
@Test
func stagesReadInTimeOrderNotStampOrder() {
    var timeline = ActionTimeline()
    timeline.stamp(.modelAnswered, at: at(9))
    timeline.stamp(.detected, at: at(0))
    timeline.stamp(.modelRequested, at: at(1))

    #expect(timeline.steps.map(\.stage) == [.detected, .modelRequested, .modelAnswered])
}

/// The elapsed figure belongs to the stage it sits on and means "time spent
/// getting here", so the model's seconds land on 모델 답변 받음 — the row a
/// person scanning the column will read them off.
@Test
func eachStageCarriesTheTimeSpentReachingIt() {
    var timeline = ActionTimeline()
    timeline.stamp(.synchronized, at: at(0))
    timeline.stamp(.modelRequested, at: at(2))
    timeline.stamp(.modelAnswered, at: at(10))

    let spans = timeline.spans

    #expect(spans[0].elapsed == nil)
    #expect(spans[1].elapsed == 2)
    #expect(spans[2].elapsed == 8)
}

/// Nil rather than zero on the first stage. Zero would read as instant when what
/// is true is that the clock started there.
@Test
func theFirstStageHasNoElapsedTime() {
    var timeline = ActionTimeline()
    timeline.stamp(.detected, at: at(0))

    #expect(timeline.spans.first?.elapsed == nil)
    #expect(timeline.duration == nil)
}

/// The queue re-reads a waiting draft every ten seconds. Without replacement a
/// draft that waited two minutes would carry a dozen identical rows and bury the
/// one line that explains the wait.
@Test
func stampingAStageTwiceKeepsOneRowWithTheLaterInstant() {
    var timeline = ActionTimeline()
    timeline.stamp(.queued, at: at(0), note: "첫 사유")
    timeline.stamp(.queued, at: at(30), note: "나중 사유")

    #expect(timeline.steps.count == 1)
    #expect(timeline.steps.first?.at == at(30))
    #expect(timeline.steps.first?.note == "나중 사유")
}

/// One reply is written down across several rows — the draft when the model
/// answers, the delivery when the queue lets it out — and the question "왜
/// 늦었나" spans all of them.
@Test
func mergingRowsRebuildsTheWholeReplyFromItsParts() {
    let drafting = ActionTimeline()
        .stamping(.detected, at: at(0))
        .stamping(.modelRequested, at: at(6))
        .stamping(.modelAnswered, at: at(14))

    let delivery = ActionTimeline()
        .stamping(.queued, at: at(14))
        .stamping(.sendAttempted, at: at(70))
        .stamping(.sent, at: at(72))

    let merged = drafting.merging(delivery)

    #expect(merged.steps.map(\.stage) == [.detected, .modelRequested, .modelAnswered, .queued, .sendAttempted, .sent])
    #expect(merged.duration == 72)
}

/// The queue stamps 전송 대기열 등록 from the entry's own creation time, which is
/// the same instant the draft row recorded. Either answer is right; taking one
/// keeps the merged list from growing a duplicate.
@Test
func mergingDoesNotDuplicateAStageBothRowsRecorded() {
    let drafting = ActionTimeline().stamping(.queued, at: at(14))
    let delivery = ActionTimeline()
        .stamping(.queued, at: at(14))
        .stamping(.sent, at: at(20))

    #expect(drafting.merging(delivery).steps.map(\.stage) == [.queued, .sent])
}

/// The reason the section exists is to point at the stage that cost the time,
/// rather than leaving the user to compare a column of numbers.
@Test
func theSlowestStageIsTheOneWithTheLongestGapBeforeIt() {
    let timeline = ActionTimeline()
        .stamping(.detected, at: at(0))
        .stamping(.synchronized, at: at(3))
        .stamping(.modelRequested, at: at(4))
        .stamping(.modelAnswered, at: at(12))
        .stamping(.sent, at: at(13))

    #expect(timeline.slowestStage == .modelAnswered)
}

/// A timeline where every gap is under a second has no story to tell, and
/// naming a winner there would be noise dressed as a finding.
@Test
func nothingIsCalledSlowestWhenEveryStageWasInstant() {
    let timeline = ActionTimeline()
        .stamping(.sendAttempted, at: at(0))
        .stamping(.sent, at: at(0.2))

    #expect(timeline.slowestStage == nil)
}

/// Rows written before this existed carry nothing, and must read as having been
/// untimed rather than as having taken no time.
@Test
func anEmptyTimelineReportsNoDuration() {
    #expect(ActionTimeline().isEmpty)
    #expect(ActionTimeline().duration == nil)
    #expect(ActionTimeline().spans.isEmpty)
}

/// Round-tripped through the column it is stored in, because a shape that
/// encodes but does not decode loses every duration on the next launch and looks
/// exactly like a pipeline that stopped recording them.
@Test
func aTimelineSurvivesBeingEncodedAndDecoded() throws {
    let timeline = ActionTimeline()
        .stamping(.detected, at: at(0))
        .stamping(.sent, at: at(9), note: "전송했습니다.")

    let data = try JSONEncoder().encode(timeline)
    let decoded = try JSONDecoder().decode(ActionTimeline.self, from: data)

    #expect(decoded == timeline)
    #expect(decoded.steps.last?.note == "전송했습니다.")
}

/// Two stamps can share an instant — the clock has finite resolution, and the
/// steps between a model answering and its draft being queued are microseconds
/// of local work. Sorting on time alone left the order to whatever the sort did
/// with equal keys, and the pane showed 채팅창 입력 시작 above 모델 답변 받음:
/// the app telling the user it sent a reply before it had one.
@Test
func stagesSharingAnInstantStillReadInPipelineOrder() {
    let moment = at(0)
    var timeline = ActionTimeline()
    timeline.stamp(.sent, at: moment)
    timeline.stamp(.queued, at: moment)
    timeline.stamp(.modelAnswered, at: moment)
    timeline.stamp(.sendAttempted, at: moment)
    timeline.stamp(.modelRequested, at: moment)

    #expect(timeline.steps.map(\.stage) == [.modelRequested, .modelAnswered, .queued, .sendAttempted, .sent])
}

/// And a later instant still wins over the pipeline order, because the record is
/// what happened rather than what was supposed to.
@Test
func aLaterInstantOutranksThePipelineOrder() {
    var timeline = ActionTimeline()
    timeline.stamp(.sent, at: at(0))
    timeline.stamp(.modelRequested, at: at(5))

    #expect(timeline.steps.map(\.stage) == [.sent, .modelRequested])
}
