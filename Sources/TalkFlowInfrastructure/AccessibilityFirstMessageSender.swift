import Foundation
import TalkFlowDomain

/// Types directly when it can and drives katok when it cannot.
///
/// The direct path is better whenever it applies: it takes no focus, and it is
/// the only one that works behind a shut lid. But it can only reach a room whose
/// window is already open on this desktop and whose title is unambiguous, and it
/// refuses rather than guess. katok covers the rest — it can open a closed room —
/// at the cost of bringing KakaoTalk forward.
///
/// Only a refusal falls through. A direct attempt that reports the message as
/// undeliverable for a reason katok would hit too is still retryable, and trying
/// katok next costs one more attempt on a screen nobody is watching.
public struct AccessibilityFirstMessageSender: MessageSender {
    private let direct: any MessageSender
    private let fallback: any MessageSender

    public init(direct: any MessageSender, fallback: any MessageSender) {
        self.direct = direct
        self.fallback = fallback
    }

    public func send(
        text: String,
        toChatRoomID chatRoomID: String,
        named chatRoomName: String,
        origin: SendOrigin
    ) async throws -> SendReceipt {
        do {
            return try await direct.send(
                text: text,
                toChatRoomID: chatRoomID,
                named: chatRoomName,
                origin: origin
            )
        } catch let failure as MessageSendFailure where failure.isRetryable {
            // A refusal about the moment is not a refusal about the method.
            // katok has no interlock of its own, so passing "somebody is typing"
            // along to it is how a message ended up in the box of whatever room
            // the user was searching for — the polite path declined and handed
            // the job to the one that would not.
            guard failure.allowsAnotherAttemptNow else { throw failure }
            // Why the cheap route was unavailable travels with the receipt. It
            // is nearly always the same sentence — the room's window is not
            // open — and knowing that is knowing why a send took twenty seconds
            // instead of one.
            let receipt = try await fallback.send(
                text: text,
                toChatRoomID: chatRoomID,
                named: chatRoomName,
                origin: origin
            )
            return SendReceipt(
                route: receipt.route,
                attempts: receipt.attempts,
                fellBackBecause: failure.message
            )
        }
    }
}
