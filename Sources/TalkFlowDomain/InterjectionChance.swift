import Foundation

/// How often a room bothers to ask the model about a message nobody addressed to
/// it.
///
/// It is the chance of *asking*, not the chance of answering. At 100 every
/// unaddressed message is still put to the model, which declines whenever it
/// judges no answer was wanted — `should_reply`, with the reason recorded beside
/// it. This dial only decides how often the question gets asked at all, which is
/// why it is settled here with a draw instead of said in the prompt.
///
/// It replaced a three-step enum — 꺼짐 / 낮음 / 보통 — that promised a gradient it
/// did not have. 낮음 and 보통 were the same value in code for months while the
/// picker offered both; when they were finally told apart it was by a local
/// question-detector that dropped a plain Korean question because it ended
/// `건가..` with no `?`. Every ending added to that list walked 낮음 back towards
/// 보통, and leaving the list alone kept throwing real questions away. A number
/// cannot lie about what it does: 40 is 40.
public struct InterjectionChance: Equatable, Sendable {
    /// 0 through 100. A value outside is brought inside rather than refused —
    /// this is a value, and the field that takes it does the refusing where the
    /// user can read why.
    public let percent: Int

    public init(percent: Int) {
        self.percent = min(max(percent, 0), 100)
    }

    /// What every room starts with, including the rooms configured before this
    /// existed. Asking every time is what 보통 did, and judging what deserves an
    /// answer is the model's job — 답변 조건 is where the user narrows it.
    public static let always = InterjectionChance(percent: 100)

    /// What 꺼짐 was: an unaddressed message never reaches the model, so only a
    /// call by name or keyword produces an answer here.
    public static let never = InterjectionChance(percent: 0)

    public var asksEveryTime: Bool { percent >= 100 }

    public var neverAsks: Bool { percent <= 0 }

    public var summary: String { "\(percent)%" }

    /// Whether a draw from `0..<1` lands inside this chance.
    ///
    /// Both ends are answered before any arithmetic, so neither can come down to
    /// a rounding: 0 must never ask and 100 must always ask, whatever was drawn.
    public func admits(_ draw: Double) -> Bool {
        if neverAsks { return false }
        if asksEveryTime { return true }
        return draw < Double(percent) / 100
    }
}

/// Draws where in `0..<1` one 끼어들기 decision falls.
///
/// A value rather than a call to `Double.random` inside the engine, for the same
/// reason `ReplyEvaluationRequest` carries its own calendar and its own
/// `JudgementRoll`: a test states the draw instead of hoping for one, and the
/// engine stays a function of what it was handed.
public struct InterjectionRoll: Sendable {
    private let fraction: @Sendable (String) -> Double

    public init(_ fraction: @escaping @Sendable (String) -> Double) {
        self.fraction = fraction
    }

    public func callAsFunction(_ key: String) -> Double {
        min(max(fraction(key), 0), 1)
    }

    /// The default: the room and the message this judgement is anchored on, mixed
    /// into `0..<1`.
    ///
    /// Derived from the subject rather than drawn fresh, so the same question
    /// gets the same answer however many times it is asked. The pipeline looks at
    /// a room again after 뒷말 대기 and again on the next sync that reports it
    /// changed; a coin flipped twice about one run would let a 40% room take a
    /// message it had already skipped, or drop one it had already taken.
    public static let fromJudgedRun = InterjectionRoll { StableFraction.of($0) }
}
