import Foundation

/// The hours of the day a room is allowed to answer.
///
/// Kept as minutes from midnight rather than as a `Date`, because what the user
/// picks is a time of day: 22시 has to still mean 22시 tomorrow, and on whatever
/// clock the Mac is running when tomorrow comes.
public struct ReplyActiveHours: Equatable, Sendable {
    /// Answers around the clock, which is what every room did before this
    /// setting existed.
    public static let always = ReplyActiveHours()

    /// Whether the window applies at all. A flag beside the times rather than an
    /// optional window, so turning the limit off and on again gives back the
    /// hours the user picked instead of a default.
    public var isLimited: Bool
    public var startMinute: Int
    public var endMinute: Int

    public init(
        isLimited: Bool = false,
        startMinute: Int = 9 * 60,
        endMinute: Int = 23 * 60
    ) {
        self.isLimited = isLimited
        self.startMinute = Self.withinTheDay(startMinute)
        self.endMinute = Self.withinTheDay(endMinute)
    }

    /// Whether a moment falls inside the window, read on the Mac's own clock.
    ///
    /// The start counts and the end does not, so 22:00–02:00 answers at 22:00 and
    /// stops at 02:00. An end earlier than the start is that same window rather
    /// than an impossible one: it runs past midnight and closes the next morning.
    public func allows(_ moment: Date, calendar: Calendar = .current) -> Bool {
        guard isLimited else { return true }
        // Two pickers left on the same time mean the whole day, not none of it. A
        // room that quietly answers nobody until the user works out why is worse
        // than one that keeps behaving as it did.
        guard startMinute != endMinute else { return true }

        let parts = calendar.dateComponents([.hour, .minute], from: moment)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)

        return startMinute < endMinute
            ? minute >= startMinute && minute < endMinute
            : minute >= startMinute || minute < endMinute
    }

    /// How many of the seconds between two instants fall inside the window.
    ///
    /// For 먼저 말 걸기's ④ 비활성 주기 정지: the opener's silence clock may be set to
    /// run only while the room is allowed to speak, so a night spent outside the
    /// hours does not count toward the wait. The whole span is active when the
    /// window does not apply — an unlimited room, or two pickers left on the same
    /// time, which `allows` also reads as the whole day — so there is nothing to
    /// subtract and the answer is simply `end - start`.
    ///
    /// Walked a day at a time rather than a minute at a time. A silence measured in
    /// days would be tens of thousands of one-minute steps; this is one intersection
    /// per calendar day the span touches, each the overlap of [start, end] with that
    /// day's open span(s). A window that runs past midnight contributes two spans on
    /// a given day — last night's tail up to the close, and today's open up to
    /// midnight — which is why `openIntervals` returns a list.
    public func activeSeconds(from start: Date, to end: Date, calendar: Calendar = .current) -> TimeInterval {
        guard end > start else { return 0 }
        guard isLimited, startMinute != endMinute else { return end.timeIntervalSince(start) }

        var total: TimeInterval = 0
        var dayStart = calendar.startOfDay(for: start)
        while dayStart < end {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }
            for span in openIntervals(on: dayStart, nextDay: nextDay, calendar: calendar) {
                let lower = max(span.open, start)
                let upper = min(span.close, end)
                if upper > lower { total += upper.timeIntervalSince(lower) }
            }
            dayStart = nextDay
        }
        return total
    }

    /// The open span(s) of one calendar day, as concrete instants on the wall
    /// clock the calendar keeps. A window that stays within the day is one span; one
    /// that crosses midnight — 22:00–02:00 — is two: midnight up to the close, and
    /// the open up to the next midnight.
    private func openIntervals(
        on dayStart: Date,
        nextDay: Date,
        calendar: Calendar
    ) -> [(open: Date, close: Date)] {
        func instant(_ minute: Int) -> Date {
            calendar.date(byAdding: .minute, value: minute, to: dayStart) ?? dayStart
        }
        if startMinute < endMinute {
            return [(instant(startMinute), instant(endMinute))]
        }
        return [(dayStart, instant(endMinute)), (instant(startMinute), nextDay)]
    }

    /// Reads back the way the user set it, including the part that is easy to
    /// misread: a window that ends on the next day.
    public var summary: String {
        guard isLimited else { return "제한 없음" }
        guard startMinute != endMinute else { return "하루 종일" }
        let window = "\(Self.clock(startMinute))–\(Self.clock(endMinute))"
        return endMinute < startMinute ? "\(window) (다음 날까지)" : window
    }

    /// A minute outside the day would make the window unsatisfiable, and a room
    /// silenced by a bad stored number gives the user nothing to go on.
    private static func withinTheDay(_ minute: Int) -> Int {
        let day = 24 * 60
        return ((minute % day) + day) % day
    }

    private static func clock(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }
}
