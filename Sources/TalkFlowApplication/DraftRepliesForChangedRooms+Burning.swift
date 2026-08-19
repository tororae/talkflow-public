import Foundation
import TalkFlowDomain

/// 집중 시간, as the pipeline sees it: read the cycle before judging, and roll
/// for a new one after answering.
///
/// Both halves are here rather than inside `ResponsePolicyEngine`, and that is
/// the point of `RoomPolicy.whileBurning` returning a whole policy. The engine
/// stays a pure function of the policy it was handed and never learns that
/// burning exists; everything downstream — the hold reasons, the record, the
/// summary on screen — reads one policy and cannot disagree about whether a room
/// is burning.
extension DraftRepliesForChangedRooms {
    /// The room's settings as they stand this instant, and the cycle they came
    /// from so the caller can roll against it afterwards.
    struct Burning {
        let policy: RoomPolicy
        let state: BurningState?
    }

    /// Applies a live burn, and ends one that 답변 활성화 시간 has closed on.
    ///
    /// The hours check is a write and not a comparison. Outside its hours a room
    /// answers nothing either way, so leaving the burn alone would look identical
    /// today and wrong tomorrow: the burn would still be running when the hours
    /// reopened, and a room would come back talkative for reasons nobody could
    /// see. It is marked as announced at the same time — the goodbye it would
    /// otherwise be owed cannot go out inside closed hours anyway, and left
    /// unspoken it would arrive at the reopening as a farewell.
    func burning(
        for room: ChatRoom,
        account: AccountProfile,
        policy: RoomPolicy,
        at now: Date
    ) async -> Burning {
        guard policy.burning.isEnabled, let store = burningStore else {
            return Burning(policy: policy, state: nil)
        }
        guard var state = try? await store.state(
            for: room.id,
            accountFingerprint: account.fingerprint
        ) else {
            return Burning(policy: policy, state: nil)
        }

        if state.isBurning(at: now), !policy.activeHours.allows(now, calendar: .current) {
            state = state.ending(at: now)
            try? await store.save(state, for: room.id, accountFingerprint: account.fingerprint)
            try? await store.markAnnounced(
                at: now,
                for: room.id,
                accountFingerprint: account.fingerprint
            )
        }

        return Burning(policy: policy.whileBurning(state, at: now), state: state)
    }

    /// Rolled after an answer went out, never before one.
    ///
    /// A burn is a room that got a reply out of somebody. Rolling on every
    /// message judged would start burns in rooms that had just declined to say
    /// anything — the app in a hurry to stay quiet — and would roll far more
    /// often than the setting reads, since most judgements are holds.
    ///
    /// Both deadlines are drawn here and written once. Drawing the end lazily
    /// would move it every time the room was looked at, which is the one thing a
    /// deadline may not do.
    func startBurnIfDrawn(
        for room: ChatRoom,
        account: AccountProfile,
        policy: RoomPolicy,
        after state: BurningState?,
        at now: Date
    ) async -> BurningState? {
        guard let store = burningStore,
              policy.startsBurning(after: state, at: now, roll: burningRoll)
        else {
            return nil
        }
        let duration = Self.draw(policy.burning.duration, roll: burningRoll)
        let cooldown = Self.draw(policy.burning.cooldown, roll: burningRoll)
        let started = BurningState(
            startedAt: now,
            endsAt: now.addingTimeInterval(duration),
            cooldownUntil: now.addingTimeInterval(duration + cooldown)
        )
        try? await store.save(started, for: room.id, accountFingerprint: account.fingerprint)
        return started
    }

    /// Where in a range this burn falls, drawn afresh rather than off the clock.
    ///
    /// `JudgementInterval.target` would have done the arithmetic, but it draws
    /// from the instant the cycle started — deliberately, so a judgement looked
    /// at twice answers the same both times. Here that property is backwards: the
    /// duration and the cooldown are drawn at the same instant, and reading them
    /// off it would tie them together, so a long burn would always be followed by
    /// a long wait and the pair would be the most readable rhythm in the app.
    private static func draw(_ interval: JudgementInterval, roll: BurningRoll) -> TimeInterval {
        guard !interval.isFixed else { return interval.shortest }
        return interval.shortest + (interval.longest - interval.shortest) * roll()
    }
}
