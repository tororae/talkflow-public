import Foundation
import Testing
@testable import TalkFlowFeatures

/// The send queue's loop turns every ten seconds and the sweeps riding it want to
/// look far less often. These state the instants rather than sleeping through a
/// minute, which is why `begin` takes one.
@MainActor
@Test
func theFirstTickASweepEverSeesIsOneItRunsOn() {
    let throttle = PollSweepThrottle(every: 60)

    #expect(throttle.begin(now: Date(timeIntervalSince1970: 0)))
}

@MainActor
@Test
func aTickInsideTheIntervalIsSkipped() {
    let throttle = PollSweepThrottle(every: 60)
    let start = Date(timeIntervalSince1970: 0)

    #expect(throttle.begin(now: start))
    #expect(!throttle.begin(now: start.addingTimeInterval(10)))
    #expect(!throttle.begin(now: start.addingTimeInterval(59)))
}

/// The interval is a floor, not a gap to clear: at exactly a minute the sweep is
/// due. Otherwise a loop turning on a round number would wait out a whole extra
/// tick every time.
@MainActor
@Test
func theTickOnTheIntervalItselfIsDue() {
    let throttle = PollSweepThrottle(every: 60)
    let start = Date(timeIntervalSince1970: 0)

    #expect(throttle.begin(now: start))
    #expect(throttle.begin(now: start.addingTimeInterval(60)))
}

/// A skipped tick must not book the clock. If it did, a loop turning six times
/// per interval would push the next due tick out on every refusal and the sweep
/// would never run again — the invisible failure this whole loop is careful about.
@MainActor
@Test
func aSkippedTickDoesNotPushTheNextOneBack() {
    let throttle = PollSweepThrottle(every: 60)
    let start = Date(timeIntervalSince1970: 0)

    #expect(throttle.begin(now: start))
    for second in stride(from: 10, through: 50, by: 10) {
        #expect(!throttle.begin(now: start.addingTimeInterval(TimeInterval(second))))
    }
    #expect(throttle.begin(now: start.addingTimeInterval(60)))
}

/// Two sweeps ride the same loop on different intervals — a minute for quiet
/// rooms, five for summaries — and each has to keep its own clock. Sharing one
/// would silently make the faster sweep as slow as the slower.
@MainActor
@Test
func sweepsOnDifferentIntervalsKeepTheirOwnClocks() {
    let opener = PollSweepThrottle(every: TalkFlowModels.conversationOpenerSweep)
    let summary = PollSweepThrottle(every: TalkFlowModels.summaryRefreshSweep)
    let start = Date(timeIntervalSince1970: 0)

    #expect(opener.begin(now: start))
    #expect(summary.begin(now: start))

    let aMinuteLater = start.addingTimeInterval(60)
    #expect(opener.begin(now: aMinuteLater))
    #expect(!summary.begin(now: aMinuteLater))

    #expect(summary.begin(now: start.addingTimeInterval(300)))
}
