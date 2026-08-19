import Foundation

/// What the Mac is doing right now, as far as the send rules care.
///
/// A sleeping display is deliberately absent. It is the strongest evidence that
/// nobody is at the keyboard, which is exactly the condition auto-send waits
/// for; treating it as a blocker would stop sending precisely when it should
/// happen. A locked screen is different — accessibility automation against
/// another app does not work there.
public struct SystemActivitySnapshot: Equatable, Sendable {
    public let idleSeconds: TimeInterval
    public let screenLocked: Bool

    public init(idleSeconds: TimeInterval, screenLocked: Bool) {
        self.idleSeconds = idleSeconds
        self.screenLocked = screenLocked
    }
}

public protocol SystemActivityMonitor: Sendable {
    func snapshot() -> SystemActivitySnapshot
}

public enum SendBlockReason: Equatable, Sendable {
    case globalPause
    case accountMismatch
    case roomNoLongerAutoSends
    case usePolicyNotAccepted
    case stillSettling(remaining: TimeInterval)
    case userIsActive(idleSeconds: TimeInterval)
    case screenLocked
    case conversationMovedOn
    case tooOld

    public var explanation: String {
        switch self {
        case .globalPause: "전역 응답이 꺼져 자동 전송을 취소했습니다."
        case .accountMismatch: "전송 직전 계정이 달라 취소했습니다."
        case .roomNoLongerAutoSends: "채팅방 정책이 자동 전송이 아니어서 취소했습니다."
        case .usePolicyNotAccepted: "전송 이용 정책에 동의하기 전에는 보내지 않습니다."
        case let .stillSettling(remaining): "안정화 시간이 \(Int(remaining.rounded()))초 남았습니다."
        case let .userIsActive(idleSeconds): "사용 중입니다. 마지막 입력 \(Int(idleSeconds.rounded()))초 전."
        case .screenLocked: "화면이 잠겨 있습니다."
        case .conversationMovedOn: "대화가 이어져 초안이 더는 맞지 않아 취소했습니다."
        case .tooOld: "초안이 오래되어 취소했습니다."
        }
    }
}

public enum SendVerdict: Equatable, Sendable {
    case send
    /// Conditions may still be met later, so the draft stays queued.
    case wait(SendBlockReason)
    /// The draft can never become correct; it is dropped.
    case cancel(SendBlockReason)
}

public struct SendGateRequest: Sendable {
    public let send: PendingSend
    public let policy: RoomPolicy
    public let globalResponsesEnabled: Bool
    public let usePolicyAccepted: Bool
    public let currentAccountFingerprint: String?
    /// The room's latest message at this moment, chronological last.
    public let latestMessageID: String?
    /// Who sent that latest message. Nil for the account's own.
    public let latestMessageSenderID: String?
    public let activity: SystemActivitySnapshot
    public let now: Date

    public init(
        send: PendingSend,
        policy: RoomPolicy,
        globalResponsesEnabled: Bool,
        usePolicyAccepted: Bool,
        currentAccountFingerprint: String?,
        latestMessageID: String?,
        latestMessageSenderID: String?,
        activity: SystemActivitySnapshot,
        now: Date = Date()
    ) {
        self.send = send
        self.policy = policy
        self.globalResponsesEnabled = globalResponsesEnabled
        self.usePolicyAccepted = usePolicyAccepted
        self.currentAccountFingerprint = currentAccountFingerprint
        self.latestMessageID = latestMessageID
        self.latestMessageSenderID = latestMessageSenderID
        self.activity = activity
        self.now = now
    }
}

/// The last check before an irreversible action.
///
/// Everything is re-verified here even though it was already true when the draft
/// was made: minutes pass between generating and sending, and the account, the
/// room policy, the conversation, and the global switch can all change in that
/// window.
public struct SendGate: Sendable {
    /// No wait by default. A reply that arrives a minute late reads as a bot
    /// catching up rather than someone talking, and in a busy room the wait was
    /// self-defeating: any message arriving inside it cancelled the draft as
    /// stale, so nothing was ever delivered. A delay can still be passed in.
    public static let defaultSettlingDelay: TimeInterval = 0
    /// Past this, a draft is no longer auto-sent: a minute on, the conversation has
    /// usually moved, and a reply landing behind it reads as a bot catching up
    /// rather than someone talking. It is not thrown away — the draft stays in
    /// review for a person to send or drop by hand. Was fifteen minutes, which let
    /// the queue deliver replies two and three minutes late into rooms that had
    /// already moved on.
    public static let defaultMaximumAge: TimeInterval = 60
    public static let defaultRequiredIdleSeconds: TimeInterval = 10

    private let maximumAge: TimeInterval
    private let requiredIdleSeconds: TimeInterval

    public init(
        maximumAge: TimeInterval = SendGate.defaultMaximumAge,
        requiredIdleSeconds: TimeInterval = SendGate.defaultRequiredIdleSeconds
    ) {
        self.maximumAge = maximumAge
        self.requiredIdleSeconds = requiredIdleSeconds
    }

    public func evaluate(_ request: SendGateRequest) -> SendVerdict {
        guard request.globalResponsesEnabled else { return .cancel(.globalPause) }
        guard request.currentAccountFingerprint == request.send.accountFingerprint else {
            return .cancel(.accountMismatch)
        }
        guard request.policy.deliveryMode.deliversAutomatically,
              request.policy.responseMode != .off,
              request.policy.responseMode != .detectOnly
        else {
            return .cancel(.roomNoLongerAutoSends)
        }

        // An opener was written for a room that had gone quiet, and that silence
        // is the whole permission it holds. Anybody at all speaking since takes
        // it away: arriving now would not be opening a conversation, it would be
        // talking over the one that just started. Unlike a reply, where several
        // people talking is a group chat rather than the subject moving on.
        if let anchor = request.send.opensConversationAfterMessageID,
           let latestMessageID = request.latestMessageID,
           latestMessageID != anchor {
            return .cancel(.conversationMovedOn)
        }

        // A reply is never cancelled for being answered-to late. It used to be:
        // if the person being answered said anything more, the draft was dropped
        // as stale. That rule was the app deciding a question it has no way to
        // answer, and it lost 113 drafts in three days — a quarter of everything
        // written — each one a model call already paid for, after an average of
        // twenty-one seconds in the queue.
        //
        // Worse than the waste, it did not converge. Every cancellation sent the
        // next sync back to draft the same room again, which took another eight
        // seconds, inside which the same person could speak again. A conversation
        // moving at conversation speed produced replies indefinitely and
        // delivered none of them.
        //
        // Whether more is still coming is now asked of the model, once, while it
        // is reading the conversation — see `FollowUpWait`. A draft that reaches
        // this gate has already been through that, so it goes out.
        //
        // An opener is different and is still cancelled above: its permission is
        // the room's silence, and anybody speaking takes that away.

        if request.now.timeIntervalSince(request.send.createdAt) > maximumAge {
            return .cancel(.tooOld)
        }

        guard request.usePolicyAccepted else { return .wait(.usePolicyNotAccepted) }

        let remaining = request.send.eligibleAt.timeIntervalSince(request.now)
        if remaining > 0 { return .wait(.stillSettling(remaining: remaining)) }

        // A locked session cannot be typed into no matter which mode is set.
        if request.activity.screenLocked { return .wait(.screenLocked) }

        // Only idle-mode waits for the user to step away. Always-on mode accepts
        // the interruption; that is what the user chose it for.
        if request.policy.deliveryMode == .autoSendWhenIdle,
           request.activity.idleSeconds < requiredIdleSeconds {
            return .wait(.userIsActive(idleSeconds: request.activity.idleSeconds))
        }

        return .send
    }
}
