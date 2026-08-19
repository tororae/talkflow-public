import Foundation
import TalkFlowDomain

/// When the cycle a room is currently accumulating into runs out.
public struct JudgementCycle: Equatable, Sendable {
    /// What the current cycle is waiting for, in whichever way this room counts.
    ///
    /// Both are fixed the moment the cycle begins: each is derived from
    /// `startedAt`, and neither a new message nor another look at the room moves
    /// it. The difference is that one of them can be put on a clock face and the
    /// other cannot — a count has no hour to name, only an amount still to come.
    public enum Ending: Equatable, Sendable {
        case at(Date)
        case afterMessages(Int)
    }

    public let startedAt: Date
    public let ends: Ending

    public init(startedAt: Date, ends: Ending) {
        self.startedAt = startedAt
        self.ends = ends
    }

    /// The instant this cycle expires, where it is measured on a clock at all.
    public var dueAt: Date? {
        guard case let .at(due) = ends else { return nil }
        return due
    }
}

/// Answers "when will this room say anything?".
///
/// The same question `InspectRecentCalls` answers for a room nobody calls, for
/// the other silence the timeline deliberately does not record. A room
/// accumulating for its next cycle holds every message and logs none of it, so
/// from outside it is indistinguishable from a broken one — and a cycle that is
/// several minutes long, or a random length, is exactly when somebody starts
/// wondering. The deadline is a real fixed point, so it can simply be shown.
public struct InspectJudgementCycle: Sendable {
    private let actionLog: any AgentActionLog
    /// Defaulted to the draw the engine uses, so the screen says what the engine
    /// will actually do rather than an estimate that happens to look similar.
    private let roll: JudgementRoll

    public init(actionLog: any AgentActionLog, roll: JudgementRoll = .fromCycleStart) {
        self.actionLog = actionLog
        self.roll = roll
    }

    /// Nil when there is no cycle to describe: the room judges every message, or
    /// it has never been asked anything and so the next message goes straight to
    /// the model.
    ///
    /// A cycle counted in messages reports the number this cycle drew, not how
    /// many are still missing. The remainder would mean reading the room's
    /// conversation on every look at the form — and the drawn number is the part
    /// the user cannot otherwise find out, since a range picks a different one
    /// each cycle.
    public func callAsFunction(
        room: ChatRoom,
        policy: RoomPolicy,
        accountFingerprint: String
    ) async -> JudgementCycle? {
        guard policy.judgesInBatches else { return nil }
        guard let startedAt = try? await actionLog.lastJudgementDate(
            chatRoomID: room.id,
            accountFingerprint: accountFingerprint
        ) else {
            return nil
        }
        guard let target = policy.judgementInterval.target(startingAt: startedAt, roll: roll) else {
            return nil
        }

        return switch target {
        case let .wait(seconds):
            JudgementCycle(startedAt: startedAt, ends: .at(startedAt.addingTimeInterval(seconds)))
        case let .messages(count):
            JudgementCycle(startedAt: startedAt, ends: .afterMessages(count))
        }
    }
}
