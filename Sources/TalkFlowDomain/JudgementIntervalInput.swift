import Foundation

/// Turns what the user typed for a cycle range into a value, or says why it will
/// not.
///
/// Beside the value rather than in the field, so the bounds are stated once and
/// the refusals can be tested without a screen. The editor used to offer a fixed
/// menu; a menu cannot express "10초에서 5분 사이", which is the whole point of a
/// range, so the numbers are typed and something has to decide which numbers are
/// numbers.
///
/// A value rather than a namespace because two settings are typed this way and
/// they do not accept the same numbers. 판단 주기 may be five seconds or ten
/// messages; 먼저 말 걸기 may be neither, and one range type with two bound sets
/// beats a second parser that drifts from this one.
public struct JudgementIntervalInput: Equatable, Sendable {
    /// One unit for both ends, chosen beside the fields.
    ///
    /// Not per field: a range that reads `10 ~ 5` with different units beside
    /// each end looks inverted, and the reader has to do arithmetic to see that
    /// it is not. One unit keeps the two numbers comparable by eye.
    ///
    /// The unit is also the mode. `개` is not a third picker to be combined with
    /// the other two — a cycle is counted one way or the other, and choosing the
    /// unit is choosing which.
    public enum Unit: String, CaseIterable, Equatable, Sendable {
        case seconds
        case minutes
        case messages

        public var title: String {
            switch self {
            case .seconds: "초"
            case .minutes: "분"
            case .messages: "개"
            }
        }

        public var measure: JudgementInterval.Measure {
            switch self {
            case .seconds, .minutes: .seconds
            case .messages: .messages
            }
        }

        /// How much of the measure one typed number is worth.
        public var span: Double {
            switch self {
            case .seconds, .messages: 1
            case .minutes: 60
            }
        }
    }

    public enum Refusal: Error, Equatable, Sendable {
        case notANumber
        case tooShort
        case tooLong
        case inverted
    }

    /// What one measure accepts, and what it takes when it is switched on without
    /// a number being named.
    public struct Bounds: Equatable, Sendable {
        public let lowest: Double
        public let highest: Double
        public let suggested: JudgementInterval
        /// What to do instead, said only where there is something else to do.
        /// Being told a number is too small is not much help when the thing the
        /// user actually wanted is a different control on the same screen.
        public let floorHint: String?

        public init(
            lowest: Double,
            highest: Double,
            suggested: JudgementInterval,
            floorHint: String? = nil
        ) {
            self.lowest = lowest
            self.highest = highest
            self.suggested = suggested
            self.floorHint = floorHint
        }
    }

    public let time: Bounds
    /// Nil where a setting can only be measured on a clock.
    public let messages: Bounds?

    public init(time: Bounds, messages: Bounds? = nil) {
        self.time = time
        self.messages = messages
    }

    /// The units this setting offers, which is what the picker shows.
    public var units: [Unit] {
        messages == nil ? [.seconds, .minutes] : Unit.allCases
    }

    /// A setting that does not offer 개 is never asked about it — `units` leaves
    /// it out — so the fallback keeps this total rather than making every caller
    /// unwrap a case it cannot reach.
    public func bounds(for unit: Unit) -> Bounds {
        switch unit.measure {
        case .seconds: time
        case .messages: messages ?? time
        }
    }

    /// An empty 최대 means "same as 최소" — a fixed cycle, which is what most rooms
    /// want and what nobody should have to type twice.
    public func interval(
        shortest: String,
        longest: String,
        unit: Unit
    ) -> Result<JudgementInterval, Refusal> {
        let bottom: TimeInterval
        switch value(shortest, in: unit) {
        case let .success(value): bottom = value
        case let .failure(refusal): return .failure(refusal)
        }

        guard !longest.trimmingCharacters(in: .whitespaces).isEmpty else {
            return .success(JudgementInterval(fixed: bottom, measure: unit.measure))
        }

        let top: TimeInterval
        switch value(longest, in: unit) {
        case let .success(value): top = value
        case let .failure(refusal): return .failure(refusal)
        }

        guard top >= bottom else { return .failure(.inverted) }
        return .success(JudgementInterval(measure: unit.measure, shortest: bottom, longest: top))
    }

    /// What the field says beside a number it would not take. The numbers come
    /// from the bounds that refused it, so a floor of 5초 and a floor of 2개
    /// cannot end up quoting each other's limit.
    public func explanation(_ refusal: Refusal, in unit: Unit) -> String {
        let bounds = bounds(for: unit)
        let counts = unit.measure == .messages
        switch refusal {
        case .notANumber:
            return "숫자로 적어 주세요."
        case .tooShort:
            let floor = "\(Self.amount(bounds.lowest, in: unit))보다 \(counts ? "적게" : "짧게")는 둘 수 없습니다."
            return [floor, bounds.floorHint].compactMap { $0 }.joined(separator: " ")
        case .tooLong:
            return "\(Self.amount(bounds.highest, in: unit))까지 넣을 수 있습니다."
        case .inverted:
            return "최대는 최소보다 \(counts ? "적을" : "짧을") 수 없습니다."
        }
    }

    /// What a field starts out holding. A setting with no number of its own
    /// borrows the suggestion rather than showing a zero the field would refuse
    /// to take back.
    public func typed(_ value: Double, in unit: Unit) -> String {
        let held = value > 0 ? value : bounds(for: unit).suggested.shortest
        return String(Int((held / unit.span).rounded()))
    }

    private func value(_ text: String, in unit: Unit) -> Result<Double, Refusal> {
        let bounds = bounds(for: unit)
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let typed = Int(trimmed) else {
            // A number too long for an `Int` is still a number, and telling its
            // author it is not one sends them hunting for a typo.
            let digits = !trimmed.isEmpty && trimmed.allSatisfy { $0.isASCII && $0.isNumber }
            return .failure(digits ? .tooLong : .notANumber)
        }

        let value = Double(typed) * unit.span
        guard value >= bounds.lowest else { return .failure(.tooShort) }
        guard value <= bounds.highest else { return .failure(.tooLong) }
        return .success(value)
    }

    /// The unit that shows a stored range without rounding part of it away.
    /// Independent of the bounds: it is about the numbers already saved.
    public static func unit(for interval: JudgementInterval) -> Unit {
        guard !interval.countsMessages else { return .messages }
        let whole = [interval.shortest, interval.longest].allSatisfy {
            $0.truncatingRemainder(dividingBy: 60) == 0
        }
        return whole ? .minutes : .seconds
    }

    /// A bound as the refusal quotes it, in the largest unit that keeps it whole.
    /// "7200초까지" is a limit the reader has to do arithmetic on.
    ///
    /// The 시간·분·초 reading is `PolicyWording`'s, so a bound quoted here and the
    /// same span printed on `!방 <N>` cannot end up worded differently. Only the
    /// clock branch: 개 counts messages, which no span formatter should try to read.
    ///
    /// `span`, not `duration`: `explanation` continues the sentence — 「5초보다 짧게는
    /// 둘 수 없습니다」 — and a bound that read 「없음」 would say 「없음보다 짧게는」.
    private static func amount(_ value: Double, in unit: Unit) -> String {
        guard unit.measure != .messages else { return "\(Int(value.rounded()))개" }
        return PolicyWording.span(value)
    }
}
