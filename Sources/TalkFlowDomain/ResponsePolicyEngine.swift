import Foundation

public enum ReplyTrigger: String, Equatable, Sendable {
    case mention
    case directQuestion
    case spontaneous
}

public enum ReplyHoldReason: Equatable, Sendable {
    case globalPause
    case accountUnverified
    case roomDisabled
    case detectOnly
    case outsideActiveHours
    case noNewMessage
    case lastMessageIsOwn
    case notAddressed
    /// Nobody called, and this room's 끼어들기 확률 did not come up. Its own reason
    /// rather than `notAddressed`, because the two say different things about a
    /// room's silence: one is nobody talking to you, the other is a dial the user
    /// set.
    case interjectionSkipped
    case nonTextMessage
    case cooldown(remaining: TimeInterval)
    case batching(remaining: TimeInterval)
    /// The same accumulation, counted in conversation instead of on a clock. Its
    /// own case rather than a second reading of `batching`: the two numbers are
    /// not the same kind of number, and a room short four messages would
    /// otherwise be reported as one short four seconds.
    case collecting(remaining: Int)

    public var explanation: String {
        switch self {
        case .globalPause: "전역 응답이 꺼져 있습니다."
        case .accountUnverified: "카카오톡 계정 확인이 끝나지 않았습니다."
        case .roomDisabled: "이 채팅방은 응답이 꺼져 있습니다."
        case .detectOnly: "이 채팅방은 감지 전용입니다."
        case .outsideActiveHours: "이 채팅방의 답변 활성화 시간이 아닙니다."
        case .noNewMessage: "평가할 새 메시지가 없습니다."
        case .lastMessageIsOwn: "마지막 메시지를 내가 보냈습니다."
        case .notAddressed: "나를 부른 메시지가 아닙니다."
        case .interjectionSkipped: "끼어들기 확률에 걸리지 않아 이 메시지는 넘어갔습니다."
        case .nonTextMessage: "텍스트가 아닌 메시지입니다."
        case let .cooldown(remaining): "최소 응답 간격이 \(Int(remaining.rounded()))초 남았습니다."
        case let .batching(remaining): "메시지를 모으는 중입니다. 다음 판단까지 \(Int(remaining.rounded()))초 남았습니다."
        case let .collecting(remaining): "메시지를 모으는 중입니다. 다음 판단까지 \(remaining)개 남았습니다."
        }
    }
}

public enum ReplyEvaluation: Equatable, Sendable {
    case ask(trigger: ReplyTrigger, triggerMessageID: String)
    case hold(reason: ReplyHoldReason)
}

/// Decides whether a message is even worth an AI call.
///
/// Everything checkable without a model is checked here, so the AI is asked once
/// about genuine candidates instead of being handed every message that arrives.
/// Message text is untrusted input: it is only ever matched against the room's
/// call signs, never read as instructions.
public struct ResponsePolicyEngine: Sendable {
    public init() {}

    public func evaluate(_ request: ReplyEvaluationRequest) -> ReplyEvaluation {
        guard request.globalResponsesEnabled else { return .hold(reason: .globalPause) }
        guard request.accountVerified else { return .hold(reason: .accountUnverified) }

        switch request.policy.responseMode {
        case .off: return .hold(reason: .roomDisabled)
        case .detectOnly: return .hold(reason: .detectOnly)
        case .mentionOnly, .automatic: break
        }

        // Asked before anything is read out of the conversation: the answer does
        // not depend on what arrived, and outside its hours a room owes the model
        // nothing at all.
        guard request.policy.activeHours.allows(request.now, calendar: request.calendar) else {
            return .hold(reason: .outsideActiveHours)
        }

        guard let latest = request.recentMessages.last else { return .hold(reason: .noNewMessage) }
        guard !latest.isFromMe else { return .hold(reason: .lastMessageIsOwn) }
        guard latest.kind == .text else { return .hold(reason: .nonTextMessage) }

        if let pacing = pacingHold(request) { return .hold(reason: pacing) }

        // Assembled once and passed down to whoever needs to know who called.
        let signs = request.callSigns
        return outcome(for: request, signs: signs, latest: latest)
    }

    /// What made this worth asking about, or which of the two silences this is.
    private func outcome(
        for request: ReplyEvaluationRequest,
        signs: CallSigns,
        latest: ChatMessage
    ) -> ReplyEvaluation {
        // A room judging in batches looks across everything it accumulated. A
        // call that arrived early in the interval is still a call when the
        // interval ends, and answering only whatever happened to be last would
        // drop it.
        if request.judgementScope.contains(where: { !$0.isFromMe && signs.matches($0.body) }) {
            return .ask(trigger: .mention, triggerMessageID: latest.id)
        }
        // A KakaoTalk 답장 pointed at something this account said is the one call
        // that needs no configuring. Somebody picked the message out and replied
        // to it; there is nothing to guess about who they meant, and no keyword
        // has to have been registered for it to count.
        if request.policy.answersReplies, request.repliesToThisAccount {
            return .ask(trigger: .mention, triggerMessageID: latest.id)
        }
        if request.policy.responseMode == .mentionOnly { return .hold(reason: .notAddressed) }
        if request.room.kind == .direct { return .ask(trigger: .directQuestion, triggerMessageID: latest.id) }

        // 끼어들기 확률, and the only thing it decides is whether to ask. Whether a
        // message nobody addressed wants an answer is a judgement the model makes
        // — the local rule that used to make it here threw away plain questions
        // for want of a `?` — so at 100% every one of them still goes, and the
        // model declines the ones it reads as not wanting an answer.
        //
        // The draw comes off the request rather than out of `Double.random`, and
        // it is keyed on the run being judged: the same room and the same run get
        // the same answer, however many times the pipeline looks at them.
        guard request.policy.interjectionChance.admits(request.interjectionRoll(request.interjectionKey)) else {
            return .hold(reason: .interjectionSkipped)
        }
        return .ask(trigger: .spontaneous, triggerMessageID: latest.id)
    }

    /// The two ways a room limits how often it speaks, and only ever one of them.
    ///
    /// They mean overlapping things — both bound the gap between answers — so a
    /// room that batches uses its cycle alone. Applying both would make a room
    /// wait out one and then the other, for a silence the user never asked for.
    ///
    /// The cycle itself is one thing counted one way, never a clock and a count
    /// asked together. Whichever of two bounds came first would be the one that
    /// decided, and in the slow rooms a count exists for that would always be the
    /// clock — which is the setting the count was added to get away from.
    private func pacingHold(_ request: ReplyEvaluationRequest) -> ReplyHoldReason? {
        guard request.policy.judgesInBatches else {
            return cooldownRemaining(request).map { .cooldown(remaining: $0) }
        }
        // The cycle starts at the instant this room was last asked anything,
        // which is already recorded — so the draw comes out the same on every
        // look instead of fresh on each sync, and a room that has never been
        // asked anything has no cycle for the next message to wait out.
        guard let start = request.lastJudgementAt,
              let target = request.policy.judgementInterval.target(
                  startingAt: start,
                  roll: request.judgementRoll
              )
        else {
            return nil
        }

        switch target {
        case let .wait(seconds):
            return remaining(from: start, of: seconds, at: request.now).map { .batching(remaining: $0) }
        case let .messages(count):
            let short = count - request.accumulatedMessageCount
            return short > 0 ? .collecting(remaining: short) : nil
        }
    }

    private func cooldownRemaining(_ request: ReplyEvaluationRequest) -> TimeInterval? {
        remaining(from: request.lastReplyAt, of: request.policy.minimumInterval, at: request.now)
    }

    private func remaining(from start: Date?, of span: TimeInterval, at now: Date) -> TimeInterval? {
        guard let start else { return nil }
        let elapsed = now.timeIntervalSince(start)
        guard elapsed < span else { return nil }
        return span - elapsed
    }
}
