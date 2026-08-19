import Foundation
import TalkFlowDomain

/// Everything a person needs to act on a draft the app wrote while they were away.
///
/// Draft-only is the default delivery mode, so this is the path most replies
/// actually take: TalkFlow proposes, the user decides.
public struct ReviewDrafts: Sendable {
    public static let defaultLimit = 50

    private let actionLog: any AgentActionLog
    private let settingsStore: any AppSettingsStore
    private let connection: any KakaoConnection
    private let sender: any MessageSender
    /// The queue the same draft may also be sitting in.
    ///
    /// A draft in an auto-sending room exists in two places at once: a row in the
    /// timeline for the user to act on, and an entry in the queue for the app to
    /// deliver. Deciding one of them left the other running — a draft dismissed
    /// at 10:11:46 was delivered by the queue at 10:13:43, which is the app
    /// sending a message its owner had declined.
    private let sendStore: (any PendingSendStore)?

    public init(
        actionLog: any AgentActionLog,
        settingsStore: any AppSettingsStore,
        connection: any KakaoConnection,
        sender: any MessageSender,
        sendStore: (any PendingSendStore)? = nil
    ) {
        self.actionLog = actionLog
        self.settingsStore = settingsStore
        self.connection = connection
        self.sender = sender
        self.sendStore = sendStore
    }

    public func pending(limit: Int = ReviewDrafts.defaultLimit) async throws -> [AgentAction] {
        try await actionLog.pendingDrafts(limit: limit)
    }

    /// Sends a draft because a person asked for it now.
    ///
    /// The idle and settling checks that guard automatic delivery do not apply —
    /// the user is present by definition. The account is still re-verified,
    /// because a draft written for one account must never leave from another.
    public func send(_ draft: AgentAction, text: String? = nil) async throws {
        let body = (text ?? draft.replyText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // Starts at the button rather than at the draft. Everything before this
        // is on the draft's own row and merges back in on screen; what this path
        // adds is how long typing into KakaoTalk took, which is the one span the
        // user can watch happening and the one they blame when it is slow.
        var timeline = ActionTimeline().stamping(.sendAttempted)
        let receipt: SendReceipt

        // Written down before it is thrown. A failure shown only in the window
        // the user is looking at is gone the moment they look away, and a send
        // that quietly left no trace is indistinguishable from one that was
        // never attempted. The draft itself stays pending, so it can be retried.
        do {
            guard !body.isEmpty else { throw ReviewError.emptyDraft }

            guard case let .connected(account) = await connection.status() else {
                throw ReviewError.accountUnavailable
            }
            guard account.fingerprint == draft.accountFingerprint else {
                throw ReviewError.accountChanged
            }

            receipt = try await sender.send(
                text: body,
                toChatRoomID: draft.chatRoomID,
                named: draft.chatRoomName,
                // The keyboard rule exists so a send does not land in the middle
                // of somebody typing. The keystroke that started this one was
                // theirs, so there is nothing here to interrupt — and refusing
                // was worse than pointless, because 「지금 키보드를 쓰고 있어」 is
                // the one refusal that is not allowed to fall back to katok.
                origin: .userRequested
            )
        } catch {
            try? await actionLog.record(
                AgentAction(
                    accountFingerprint: draft.accountFingerprint,
                    chatRoomID: draft.chatRoomID,
                    chatRoomName: draft.chatRoomName,
                    kind: .failed,
                    triggerMessageID: draft.triggerMessageID,
                    replyMode: draft.replyMode,
                    detail: error.localizedDescription,
                    timeline: timeline.stamping(.failed, note: error.localizedDescription)
                )
            )
            throw error
        }

        // Delivered by hand, so the queue's copy has nothing left to do. Left
        // waiting it would deliver the same words a second time the moment its
        // conditions were met.
        await withdrawFromQueue(draft, state: .sent, detail: "검토 후 직접 전송했습니다.")

        timeline.stamp(.sent, note: receipt.explanation)
        try await actionLog.record(
            AgentAction(
                accountFingerprint: draft.accountFingerprint,
                chatRoomID: draft.chatRoomID,
                chatRoomName: draft.chatRoomName,
                kind: .sent,
                triggerMessageID: draft.triggerMessageID,
                replyMode: draft.replyMode,
                replyText: body,
                detail: text == nil ? "검토 후 전송했습니다." : "수정 후 전송했습니다.",
                timeline: timeline
            )
        )
    }

    /// 무시 has to reach the queue as well as the record.
    ///
    /// The queue is cancelled first. If writing the timeline row then fails the
    /// draft comes back into the pending list and can be dismissed again, which
    /// is a nuisance; the other order fails by sending a message the user said
    /// no to, which is not recoverable at all.
    public func dismiss(_ draft: AgentAction) async throws {
        await withdrawFromQueue(draft, state: .cancelled, detail: "사용자가 초안을 무시했습니다.")
        try await actionLog.dismissDraft(id: draft.id)
    }

    /// Takes the queue's copy of this draft out of circulation.
    ///
    /// Matched on the room and the trigger message, which is the pair the queue
    /// itself keys on. Every waiting entry for that pair goes, not just the first:
    /// one decision by a person settles the message, however many rows are
    /// carrying it.
    private func withdrawFromQueue(
        _ draft: AgentAction,
        state: PendingSend.State,
        detail: String
    ) async {
        guard let sendStore,
              let triggerMessageID = draft.triggerMessageID,
              let waiting = try? await sendStore.waiting()
        else {
            return
        }

        for send in waiting
        where send.chatRoomID == draft.chatRoomID && send.triggerMessageID == triggerMessageID {
            try? await sendStore.resolve(id: send.id, state: state, detail: detail)
        }
    }

    public func usePolicyAccepted() async -> Bool {
        (try? await settingsStore.sendUsePolicyAccepted()) ?? false
    }
}

public enum ReviewError: LocalizedError {
    case emptyDraft
    case accountUnavailable
    case accountChanged

    public var errorDescription: String? {
        switch self {
        case .emptyDraft: "보낼 내용이 비어 있습니다."
        case .accountUnavailable: "카카오톡 연결을 확인하지 못했습니다."
        case .accountChanged: "이 초안을 만든 계정과 지금 로그인된 계정이 다릅니다."
        }
    }
}
