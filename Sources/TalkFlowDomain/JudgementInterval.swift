import Foundation

/// How much of a room's conversation goes by before the model is asked about it.
///
/// A range rather than one number. A room that answers at exactly 300.000 second
/// intervals is recognisable as a machine from the timing alone, whatever it
/// says, so the cycle is drawn from between the two ends. Equal ends are a fixed
/// cycle, which is still what most rooms want.
///
/// Zero at both ends is `즉시`: the room is judged as each message arrives, and
/// nothing accumulates. It stays the default — batching changes when a room
/// answers, and no other setting may turn it on by implication.
public struct JudgementInterval: Equatable, Sendable {
    /// What the two ends count: seconds, or messages from other people.
    ///
    /// Two units because rooms move at wildly different speeds. Five minutes is
    /// dozens of messages in a busy group and none at all in a room that talks
    /// twice a day, so one number of seconds cannot mean the same amount of
    /// conversation in two rooms — the user has to re-derive it per room from a
    /// message rate the app never shows them. A count means the same thing
    /// everywhere by construction: ten messages is ten messages.
    ///
    /// The clock stays because it is the only one of the two that bounds how late
    /// an answer can be. Neither is right for every room, which is why the choice
    /// is here and not decided for the user.
    public enum Measure: String, Equatable, Sendable {
        case seconds
        case messages

        /// What the two ends of the range are called on screen. "가장 짧게 10개"
        /// is not a thing anybody says.
        public var shortestTitle: String {
            switch self {
            case .seconds: "가장 짧게"
            case .messages: "가장 적게"
            }
        }

        public var longestTitle: String {
            switch self {
            case .seconds: "가장 길게"
            case .messages: "가장 많게"
            }
        }
    }

    /// What the two ends count. Both ends always mean the same thing: a cycle
    /// that was five messages at one end and five minutes at the other would be
    /// two settings wearing one name.
    public let measure: Measure
    /// The bottom of one cycle, in whatever `measure` counts. Zero means `즉시`.
    public let shortest: Double
    /// The top. Never below `shortest`; the initialiser raises it rather than
    /// letting an inverted pair exist as a value.
    public let longest: Double

    public init(measure: Measure = .seconds, shortest: Double, longest: Double) {
        let floor = max(shortest, 0)
        // 즉시 keeps no numbers, so it may not keep a unit either. Otherwise two
        // rooms that both judge every message would compare unequal because one
        // of them was last left on 개, and the picker would have two ways of
        // saying the same nothing.
        self.measure = floor > 0 ? measure : .seconds
        self.shortest = floor
        self.longest = max(longest, floor)
    }

    public init(fixed value: Double, measure: Measure = .seconds) {
        self.init(measure: measure, shortest: value, longest: value)
    }

    public static let immediate = JudgementInterval(fixed: 0)

    /// Whether this room accumulates messages and answers them together.
    public var batches: Bool { shortest > 0 }

    public var isFixed: Bool { longest == shortest }

    /// Whether this cycle is counted in conversation rather than on a clock.
    public var countsMessages: Bool { measure == .messages }

    /// Where the cycle that began at `start` ends.
    ///
    /// Drawn from the cycle's own start instant rather than freshly each time the
    /// question is asked. The pipeline re-evaluates a room on every sync, and a
    /// cycle rolled at each of those would collapse the range to its shortest
    /// end: whichever roll lands short fires, and the ones that landed long never
    /// get to expire. Deriving it from the start means every look inside one
    /// cycle gets the same answer and the next cycle — a different start — gets
    /// its own, with no rolled number to store or to fall out of step.
    ///
    /// One method for both units rather than two the caller chooses between: a
    /// cycle counted in messages has no wait, and a caller that asked for one
    /// anyway would be handed a number that means messages and reads as seconds.
    public func target(
        startingAt start: Date,
        roll: JudgementRoll = .fromCycleStart
    ) -> JudgementTarget? {
        guard batches else { return nil }
        let drawn = isFixed ? shortest : shortest + (longest - shortest) * roll(start)
        switch measure {
        case .seconds: return .wait(drawn)
        case .messages: return .messages(Int(drawn.rounded()))
        }
    }

    /// What this reads as on screen. In the domain beside the other titles rather
    /// than in the editor, because the room's footnote, the settings card and the
    /// interval field all have to call the same range the same thing.
    public var summary: String {
        guard batches else { return "즉시" }
        guard !isFixed else { return "\(amount(shortest))마다" }
        return "\(amount(shortest))~\(amount(longest))마다"
    }

    /// The clock ends read in the largest unit that keeps the number whole — 먼저 말
    /// 걸기 is measured in hours, and "180분~360분마다" is a cadence the reader has to
    /// work out. That reading is `PolicyWording`'s, one copy shared with the console
    /// and the range fields.
    ///
    /// `span`, not `duration`: `summary` appends 마다 to this, and a field that
    /// answers 「없음」 for a small number would compose into 「없음마다」.
    private func amount(_ value: Double) -> String {
        switch measure {
        case .seconds: PolicyWording.span(value)
        case .messages: "\(Int(value.rounded()))개"
        }
    }
}

/// Where one accumulation cycle ends: after so long, or after so much said.
public enum JudgementTarget: Equatable, Sendable {
    /// Seconds from the instant the cycle began.
    case wait(TimeInterval)
    /// Messages from other people, since the instant the cycle began.
    case messages(Int)

    /// The wait, where this cycle is measured on a clock at all.
    ///
    /// For 먼저 말 걸기, which is only ever measured that way — its field does not
    /// offer 개 and its column keeps no unit. Everything that can genuinely be
    /// either switches on the case instead.
    public var wait: TimeInterval? {
        guard case let .wait(seconds) = self else { return nil }
        return seconds
    }
}

/// Draws where in a range one cycle falls, as a fraction of it.
///
/// A value rather than a call to `Double.random` inside the engine, for the same
/// reason `ReplyEvaluationRequest` carries its own clock: a test states the roll
/// instead of hoping for one, and the engine stays a function of its input.
public struct JudgementRoll: Sendable {
    private let fraction: @Sendable (Date) -> Double

    public init(_ fraction: @escaping @Sendable (Date) -> Double) {
        self.fraction = fraction
    }

    public func callAsFunction(_ start: Date) -> Double {
        min(max(fraction(start), 0), 1)
    }

    /// The default: the cycle's start instant, mixed into `0..<1`.
    ///
    /// Shared with the 끼어들기 draw, which needs the same property for the same
    /// reason — see `StableFraction` for why neither may go through `Hasher`.
    public static let fromCycleStart = JudgementRoll { start in
        StableFraction.of(UInt64(bitPattern: Int64((start.timeIntervalSince1970 * 1000).rounded())))
    }
}
