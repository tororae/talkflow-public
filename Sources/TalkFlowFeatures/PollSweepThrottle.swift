import Foundation

/// The gate a sweep riding the send queue's poll passes through: how often it is
/// allowed to look, and the last tick it let through.
///
/// Its own type because every sweep on that loop needs the same three lines — if
/// the last look was less than the interval ago, this tick is not one — and each
/// sweep having written its own copy is the failure `pollSweeps` was made a list
/// for. A sweep that gets that gate wrong stops happening, and a sweep that
/// stops happening says nothing about it. Here the interval is the only thing a
/// new sweep has to state.
///
/// A reference type so the sweep that owns it can gate itself from inside its own
/// closure, without a stored property and a method on `TalkFlowModels` per sweep.
/// `@MainActor` because that is where the poll's work is already done, and it is
/// what makes the mutable instant safe to hold in the `@Sendable` closure the
/// queue calls.
@MainActor
final class PollSweepThrottle {
    private let interval: TimeInterval
    private var lastSweep: Date?

    init(every interval: TimeInterval) {
        self.interval = interval
    }

    /// True on the ticks the sweep is due for, and it books the tick as it says
    /// so. Skipped ticks are simply skipped rather than run late: what these
    /// sweeps wait for moves in minutes or hours, so the next tick is soon enough.
    ///
    /// `now` is a parameter so a test can state the instant instead of sleeping
    /// through a real interval.
    func begin(now: Date = Date()) -> Bool {
        if let lastSweep, now.timeIntervalSince(lastSweep) < interval {
            return false
        }
        lastSweep = now
        return true
    }
}
