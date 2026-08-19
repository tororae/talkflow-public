import Foundation

/// 집중 시간 — a stretch where a room answers like somebody who sat down at it.
///
/// Every other pacing setting in this app is a constant: a room answers 10% of
/// what it sees, every hour of every day, forever. Nobody behaves that way. A
/// person is away, then they are on the chat for twenty minutes answering
/// everything, then they are gone again. This is that shape, and it is the only
/// setting here that changes what the other settings mean while it is on.
///
/// What it swaps is named rather than scaled. An earlier reading of this had a
/// 상승폭 — "raise the chance by 40 points" — and that leaves the question a user
/// actually asks unanswered: a 10% room and an 80% room would burn at wildly
/// different rates from the same setting, and neither number appears anywhere on
/// screen. The values here are the values in force during a burn.
public struct BurningMode: Equatable, Sendable {
    public var isEnabled: Bool

    /// Rolled once each time this room answers. Hitting it starts a burn.
    ///
    /// A single number and not a range, unlike the two below, because a range
    /// here would be decoration. Drawing a probability from `a...b` and then
    /// rolling against it fires exactly as often as rolling against `(a+b)/2` —
    /// the arithmetic is the same and nothing about the result is observable.
    /// A duration drawn from a range *is* observable: that burn lasted eleven
    /// minutes and the last one lasted four.
    public var chance: InterjectionChance

    /// How long a burn lasts, drawn fresh each time it starts.
    ///
    /// A `JudgementInterval` because that type already means "a period drawn
    /// from a range, settled once at the start and held for the whole of it" —
    /// the same thing 먼저 말 걸기 needed. Only its time measure is used here;
    /// counting a burn in messages would end it early in exactly the rooms it
    /// exists for.
    public var duration: JudgementInterval

    /// How long after a burn before another can start. Also drawn per burn, so
    /// the gaps are not a clock anyone can read either.
    public var cooldown: JudgementInterval

    /// 끼어들기 확률 while burning. Absolute, not a bonus.
    public var interjectionChance: InterjectionChance
    /// 최소 응답 간격 while burning.
    public var minimumInterval: TimeInterval
    /// 판단 주기 while burning.
    public var judgementInterval: JudgementInterval

    public init(
        isEnabled: Bool = false,
        chance: InterjectionChance = InterjectionChance(percent: 10),
        duration: JudgementInterval = BurningMode.defaultDuration,
        cooldown: JudgementInterval = BurningMode.defaultCooldown,
        interjectionChance: InterjectionChance = InterjectionChance(percent: 90),
        minimumInterval: TimeInterval = 0,
        judgementInterval: JudgementInterval = .immediate
    ) {
        self.isEnabled = isEnabled
        self.chance = chance
        self.duration = duration
        self.cooldown = cooldown
        self.interjectionChance = interjectionChance
        self.minimumInterval = minimumInterval
        self.judgementInterval = judgementInterval
    }

    /// Off, like 먼저 말 걸기 and for the same reason: it makes a room behave
    /// differently from how its own settings read, and nothing may turn that on
    /// by implication.
    public static let off = BurningMode()

    /// Ten to twenty-five minutes. Long enough to be a stretch of conversation
    /// rather than a burst, short enough that somebody who left the app running
    /// does not find an hour of it.
    public static let defaultDuration = JudgementInterval(
        measure: .seconds,
        shortest: 600,
        longest: 1_500
    )

    /// Two to six hours. A person who was just on the chat for twenty minutes is
    /// not back twenty minutes later.
    public static let defaultCooldown = JudgementInterval(
        measure: .seconds,
        shortest: 7_200,
        longest: 21_600
    )
}

/// Where a room is in the cycle right now.
///
/// Kept apart from `BurningMode` because one is a setting and the other is a
/// fact: the settings are the user's and survive a restart untouched, while this
/// is drawn, expires on its own, and belongs to whatever this room happens to be
/// doing at this moment.
public struct BurningState: Equatable, Sendable {
    public let startedAt: Date
    /// When this burn stops. Drawn from `duration` when it started, so the number
    /// does not move underneath a room that is already burning.
    public let endsAt: Date
    /// When the next burn may start. Drawn at the same moment, for the same
    /// reason.
    public let cooldownUntil: Date

    public init(startedAt: Date, endsAt: Date, cooldownUntil: Date) {
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.cooldownUntil = cooldownUntil
    }

    public func isBurning(at now: Date) -> Bool { now < endsAt }

    /// This burn, stopped early.
    ///
    /// 답변 활성화 시간 closing is the one thing allowed to cut a burn short, and
    /// it has to actually cut it rather than merely outrank it: the room stops
    /// answering either way, but a burn left running would still be running when
    /// the hours reopen hours later, and the room would come back talkative for
    /// reasons nobody could see.
    ///
    /// The cooldown is left where it was drawn. The room burned for less than it
    /// drew and waits the same as it would have — shortening the wait to match
    /// would let a room whose hours close every evening burn twice a day forever.
    public func ending(at now: Date) -> BurningState {
        BurningState(
            startedAt: startedAt,
            endsAt: min(endsAt, now),
            cooldownUntil: cooldownUntil
        )
    }

    /// A burn that has ended but whose cooldown has not. The room is behaving
    /// normally again; it just cannot start another one yet.
    public func isCoolingDown(at now: Date) -> Bool {
        now >= endsAt && now < cooldownUntil
    }

    /// Whether this burn has ended without anything having said so yet.
    ///
    /// Asked by the pipeline rather than answered on a timer: nothing in this app
    /// runs on a clock, and a burn that ended while the room was asleep should
    /// announce itself when the room is next looked at, not never.
    public func hasJustEnded(at now: Date, announcedAt: Date?) -> Bool {
        guard now >= endsAt else { return false }
        guard let announcedAt else { return true }
        return announcedAt < endsAt
    }
}

/// Decides whether one answer starts a burn, and how long it runs.
///
/// A value for the same reason `InterjectionRoll` is one: a test states the draw
/// rather than hoping for it, and nothing in the engine reaches for
/// `Double.random`. Unlike the interjection draw this one is *not* derived from
/// the run being judged — the same message must not always start a burn, or the
/// cadence this exists to break would be the most readable one in the app.
public struct BurningRoll: Sendable {
    private let fraction: @Sendable () -> Double

    public init(_ fraction: @escaping @Sendable () -> Double) {
        self.fraction = fraction
    }

    public func callAsFunction() -> Double {
        min(max(fraction(), 0), 1)
    }

    public static let random = BurningRoll { Double.random(in: 0..<1) }
    public static let never = BurningRoll { 1 }
    public static let always = BurningRoll { 0 }
}

extension RoomPolicy {
    /// This room's settings as they stand right now, with a burn applied if one
    /// is running.
    ///
    /// A whole policy back rather than three values, so everything downstream —
    /// the engine, the summary on screen, the record — reads one thing and cannot
    /// disagree about whether a room is burning. The three swapped fields are the
    /// three that decide pace; nothing about *what* the room says changes, which
    /// is why 답변 조건 and 응답 스타일 are not here.
    public func whileBurning(_ state: BurningState?, at now: Date) -> RoomPolicy {
        guard burning.isEnabled, let state, state.isBurning(at: now) else { return self }
        var burned = self
        burned.interjectionChance = burning.interjectionChance
        burned.minimumInterval = burning.minimumInterval
        burned.judgementInterval = burning.judgementInterval
        return burned
    }

    /// Whether an answer just given may start a burn.
    ///
    /// Asked after answering rather than before, because a burn is a room that
    /// got a reply out of somebody — starting one on a message nobody answered
    /// would put the app in a hurry to say nothing.
    public func startsBurning(after state: BurningState?, at now: Date, roll: BurningRoll) -> Bool {
        guard burning.isEnabled else { return false }
        if let state, now < state.cooldownUntil { return false }
        return burning.chance.admits(roll())
    }
}
