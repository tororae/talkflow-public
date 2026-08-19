import Foundation

/// Why a delivery attempt did not go through.
///
/// The distinction that matters is whether the same draft can be tried again.
/// The connector refuses to type when KakaoTalk is not frontmost — nothing is
/// delivered and a later attempt can succeed — so treating that as terminal
/// would silently drop a message the user asked to be sent.
public struct MessageSendFailure: LocalizedError, Equatable, Sendable {
    /// The one distinction beyond retryability that a person can act on.
    ///
    /// A closed room is retryable forever and never succeeds on its own: the
    /// connector cannot reach a conversation whose window is not open, so the
    /// queue retries in silence until the draft ages out. Watching a reply sit
    /// unsent for ten minutes with the reason buried in a database column is how
    /// this case earned a name of its own.
    public enum Cause: String, Equatable, Sendable {
        case roomWindowClosed
        /// Somebody is using the keyboard this send would have taken.
        ///
        /// Unlike every other refusal this one is not about the path: it says
        /// the moment is wrong, so a second way of sending must not be tried
        /// either. Reading it as "this way did not work" is what let a polite
        /// refusal hand the job to a tool with no such scruple.
        case keyboardInUse
        case unspecified
    }

    public let message: String
    public let isRetryable: Bool
    public let cause: Cause

    public init(message: String, isRetryable: Bool, cause: Cause = .unspecified) {
        self.message = message
        self.isRetryable = isRetryable
        self.cause = cause
    }

    /// What a person is shown. When they have to do something, that comes first
    /// and in their own language; the connector's wording is not it.
    public var explanation: String {
        switch cause {
        case .roomWindowClosed:
            "카카오톡에서 이 방의 대화창이 닫혀 있어 보내지 못했습니다. 이 방의 대화창을 열어두어야 보낼 수 있습니다."
        case .keyboardInUse, .unspecified:
            message
        }
    }

    /// Whether another way of sending may be tried after this one refused.
    ///
    /// Only ever false for a refusal about the moment rather than the method.
    public var allowsAnotherAttemptNow: Bool {
        cause != .keyboardInUse
    }

    /// Whether retrying is pointless until somebody does something.
    public var needsUserAction: Bool {
        cause == .roomWindowClosed
    }

    public var errorDescription: String? { explanation }
}

/// Brings the display back so UI automation has a frontmost app to target.
///
/// A locked screen owns the front, and nothing can be typed into KakaoTalk while
/// it does. Waking works only inside the grace period before macOS starts asking
/// for a password; after that the screen stays locked and the draft keeps waiting.
public protocol DisplayWaker: Sendable {
    func wake() async
}
