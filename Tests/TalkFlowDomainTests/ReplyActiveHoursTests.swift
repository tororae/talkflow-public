import Foundation
import Testing
@testable import TalkFlowDomain

/// A window is a wall-clock time, so every check is stated on one clock rather
/// than on wherever the machine running the test happens to be.
private let seoul: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .gmt
    return calendar
}()

@Test
func aRoomWithNoLimitAnswersAtAnyHour() {
    let hours = ReplyActiveHours.always

    #expect(hours.isLimited == false)
    #expect(hours.allows(moment(3, 20), calendar: seoul))
    #expect(hours.allows(moment(14, 0), calendar: seoul))
    #expect(hours.summary == "제한 없음")
}

@Test
func aWindowAnswersInsideItselfAndHoldsOutside() {
    let hours = ReplyActiveHours(isLimited: true, startMinute: 9 * 60, endMinute: 18 * 60)

    #expect(hours.allows(moment(9, 0), calendar: seoul))
    #expect(hours.allows(moment(13, 30), calendar: seoul))
    #expect(!hours.allows(moment(8, 59), calendar: seoul))
    #expect(!hours.allows(moment(23, 30), calendar: seoul))
    #expect(hours.summary == "09:00–18:00")
}

/// 22:00–02:00 is one window that closes the next morning, not an empty one.
/// Reading it as start-before-end is the mistake that silences a room all night.
@Test
func aWindowThatEndsBeforeItStartsRunsPastMidnight() {
    let hours = ReplyActiveHours(isLimited: true, startMinute: 22 * 60, endMinute: 2 * 60)

    #expect(hours.allows(moment(22, 0), calendar: seoul))
    #expect(hours.allows(moment(23, 59), calendar: seoul))
    #expect(hours.allows(moment(0, 0), calendar: seoul))
    #expect(hours.allows(moment(1, 59), calendar: seoul))
    #expect(!hours.allows(moment(2, 0), calendar: seoul))
    #expect(!hours.allows(moment(12, 0), calendar: seoul))
    #expect(!hours.allows(moment(21, 59), calendar: seoul))
    #expect(hours.summary == "22:00–02:00 (다음 날까지)")
}

/// Otherwise a room set to 09:00–18:00 and one set to 18:00–09:00 would both
/// answer at 18:00, and neither user would be able to say which.
@Test
func theStartCountsAndTheEndDoesNot() {
    let day = ReplyActiveHours(isLimited: true, startMinute: 9 * 60, endMinute: 18 * 60)
    let night = ReplyActiveHours(isLimited: true, startMinute: 18 * 60, endMinute: 9 * 60)

    #expect(!day.allows(moment(18, 0), calendar: seoul))
    #expect(night.allows(moment(18, 0), calendar: seoul))
    #expect(day.allows(moment(9, 0), calendar: seoul))
    #expect(!night.allows(moment(9, 0), calendar: seoul))
}

/// A room that answers nobody until the user works out that two pickers match
/// is worse than one that goes on behaving as it did.
@Test
func matchingStartAndEndMeanTheWholeDayRatherThanNone() {
    let hours = ReplyActiveHours(isLimited: true, startMinute: 9 * 60, endMinute: 9 * 60)

    #expect(hours.allows(moment(9, 0), calendar: seoul))
    #expect(hours.allows(moment(4, 0), calendar: seoul))
    #expect(hours.summary == "하루 종일")
}

@Test
func aStoredMinuteOutsideTheDayIsFoldedBackIntoIt() {
    let hours = ReplyActiveHours(isLimited: true, startMinute: 25 * 60, endMinute: -60)

    #expect(hours.startMinute == 60)
    #expect(hours.endMinute == 23 * 60)
    #expect(hours.summary == "01:00–23:00")
}

// MARK: - activeSeconds

/// With no window there is nothing to subtract, so every second between the two
/// instants counts. This is the ④ off case, and the whole-day case with it.
@Test
func activeSecondsWithNoWindowCountsTheWholeSpan() {
    #expect(ReplyActiveHours.always.activeSeconds(from: moment(10, 0), to: moment(14, 0), calendar: seoul) == 4 * 3600)

    let allDay = ReplyActiveHours(isLimited: true, startMinute: 9 * 60, endMinute: 9 * 60)
    #expect(allDay.activeSeconds(from: moment(1, 0), to: moment(23, 0), calendar: seoul) == 22 * 3600)
}

/// A span that sits wholly inside the window is all active; nothing is outside to
/// drop.
@Test
func activeSecondsInsideTheWindowCountsEveryPassingSecond() {
    let hours = ReplyActiveHours(isLimited: true, startMinute: 9 * 60, endMinute: 18 * 60)

    #expect(hours.activeSeconds(from: moment(10, 0), to: moment(16, 0), calendar: seoul) == 6 * 3600)
}

/// A span that starts before the window opens and ends after it closes keeps only
/// the open middle — the hours before nine and after six do not count.
@Test
func activeSecondsClipsToTheOpenPartOfTheWindow() {
    let hours = ReplyActiveHours(isLimited: true, startMinute: 9 * 60, endMinute: 18 * 60)

    #expect(hours.activeSeconds(from: moment(7, 0), to: moment(20, 0), calendar: seoul) == 9 * 3600)
}

/// A span entirely outside the window counts nothing, which is the whole point of
/// ④: a silence that fell in the closed hours does not run the wait down at all.
@Test
func activeSecondsOutsideTheWindowCountsNothing() {
    let hours = ReplyActiveHours(isLimited: true, startMinute: 9 * 60, endMinute: 18 * 60)

    #expect(hours.activeSeconds(from: moment(19, 0), to: moment(22, 0), calendar: seoul) == 0)
}

/// A window that runs past midnight is two open spans on the days it touches, and
/// a span crossing the same midnight has to pick up both halves. 21:00→03:00 is
/// six hours on the clock, four of them inside a 22:00–02:00 window.
@Test
func activeSecondsHandlesAWindowThatRunsPastMidnight() {
    let hours = ReplyActiveHours(isLimited: true, startMinute: 22 * 60, endMinute: 2 * 60)

    #expect(hours.activeSeconds(from: dayTime(14, 21), to: dayTime(15, 3), calendar: seoul) == 4 * 3600)
}

/// A silence spanning several days sums each day's open window, partial ends
/// included. 12:00 on day one to 12:00 on day three across a 09:00–18:00 window is
/// six hours the first day, nine the second, three the third.
@Test
func activeSecondsSumsTheOpenWindowAcrossSeveralDays() {
    let hours = ReplyActiveHours(isLimited: true, startMinute: 9 * 60, endMinute: 18 * 60)

    #expect(hours.activeSeconds(from: dayTime(14, 12), to: dayTime(16, 12), calendar: seoul) == 18 * 3600)
}

/// An empty or reversed span is zero rather than a negative number the wait would
/// then never reach.
@Test
func activeSecondsIsZeroForAnEmptyOrReversedSpan() {
    let hours = ReplyActiveHours(isLimited: true, startMinute: 9 * 60, endMinute: 18 * 60)

    #expect(hours.activeSeconds(from: moment(12, 0), to: moment(12, 0), calendar: seoul) == 0)
    #expect(hours.activeSeconds(from: moment(14, 0), to: moment(10, 0), calendar: seoul) == 0)
}

// MARK: - Fixtures

private func moment(_ hour: Int, _ minute: Int) -> Date {
    dayTime(14, hour, minute)
}

private func dayTime(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    seoul.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute))
        ?? Date(timeIntervalSince1970: 0)
}
