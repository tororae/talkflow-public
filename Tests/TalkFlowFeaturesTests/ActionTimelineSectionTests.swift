import Foundation
import Testing
import TalkFlowDomain
@testable import TalkFlowFeatures

private let start = Date(timeIntervalSince1970: 1_000_000)

private func at(_ seconds: TimeInterval) -> Date {
    start.addingTimeInterval(seconds)
}

/// The pane's own reading of a reply that spent its time in the model: each row
/// says when it happened and how long getting there took, and the total is said
/// once so nobody adds the column up.
@Test
func aSectionSaysWhenEachStageHappenedAndHowLongItTook() throws {
    let timeline = ActionTimeline()
        .stamping(.detected, at: at(0))
        .stamping(.synchronized, at: at(4))
        .stamping(.modelRequested, at: at(5))
        .stamping(.modelAnswered, at: at(13))

    let section = try #require(ActionTimelineSection.of(timeline))

    #expect(section.rows.map(\.stage) == [.detected, .synchronized, .modelRequested, .modelAnswered])
    #expect(section.rows[0].elapsed == nil)
    #expect(section.rows[1].elapsed == "4.0초")
    #expect(section.rows[3].elapsed == "8.0초")
    #expect(section.total == "13.0초")
}

/// One row is marked so the eye lands on the answer instead of comparing every
/// number in the column.
@Test
func theSlowestStageIsTheOnlyOneMarked() throws {
    let timeline = ActionTimeline()
        .stamping(.modelRequested, at: at(0))
        .stamping(.modelAnswered, at: at(8))
        .stamping(.sent, at: at(9))

    let section = try #require(ActionTimelineSection.of(timeline))

    #expect(section.rows.filter(\.isSlowest).map(\.stage) == [.modelAnswered])
}

/// A single stamp records that something happened, not that it took no time, so
/// there is nothing to draw. Same for the rows written before timings existed.
@Test
func thereIsNoSectionForARowThatWasNeverTimed() {
    #expect(ActionTimelineSection.of(ActionTimeline()) == nil)
    #expect(ActionTimelineSection.of(ActionTimeline().stamping(.sent, at: at(0))) == nil)
}

/// Tenths below a minute because the differences that matter here are seconds;
/// minutes above it because "127.4초" is a number nobody converts in their head.
@Test
func durationsReadAsSecondsUntilTheyAreLongEnoughToReadAsMinutes() {
    #expect(ActionTimelineSection.duration(0.44) == "0.4초")
    #expect(ActionTimelineSection.duration(8.16) == "8.2초")
    #expect(ActionTimelineSection.duration(59.9) == "59.9초")
    #expect(ActionTimelineSection.duration(120) == "2분")
    #expect(ActionTimelineSection.duration(125) == "2분 5초")
}

/// A clock that ran backwards between two rows must not print a negative wait.
/// The instants come from two different writes, and the machine's wall clock is
/// free to move between them.
@Test
func aBackwardsGapIsShownAsNoTimeRatherThanNegativeTime() {
    #expect(ActionTimelineSection.duration(-3) == "0.0초")
}
