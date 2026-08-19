import Foundation
import TalkFlowDomain

/// Looks for a room that has gone quiet and asks the model whether there is
/// anything worth saying into it.
///
/// Every other path in this app starts from a message arriving. This one cannot:
/// a room that has gone quiet is by definition not reporting changes, so
/// `DraftRepliesForChangedRooms` will never look at it again. It is driven by the
/// send queue's poll instead of a timer of its own — the queue already wakes for
/// conditions nothing announces, and a quiet room is one more of those.
///
/// Which means this runs on a clock for as long as the app is open, so it is
/// built to cost nothing when nobody asked for it: one local query answers "does
/// any room want this at all", and everything expensive — verifying the account,
/// listing rooms, reading conversations — sits behind that answer.
public struct OpenConversationsInQuietRooms: Sendable {
    let connection: any KakaoConnection
    let policyStore: any RoomPolicyStore
    let settingsStore: any AppSettingsStore
    let actionLog: any AgentActionLog
    let generator: any ReplyGenerator
    let sendStore: (any PendingSendStore)?
    /// The room's standing 요약, the second place an opener looks for a subject
    /// once the recent messages have nothing left to continue. Optional and read
    /// only when the room 대화를 기억 — a room without it opens from the thread alone,
    /// exactly as before this was wired in.
    let summaryStore: (any ConversationSummaryStore)?
    let settlingDelay: TimeInterval
    private let gate: ConversationOpenerGate

    public init(
        connection: any KakaoConnection,
        policyStore: any RoomPolicyStore,
        settingsStore: any AppSettingsStore,
        actionLog: any AgentActionLog,
        generator: any ReplyGenerator,
        sendStore: (any PendingSendStore)? = nil,
        summaryStore: (any ConversationSummaryStore)? = nil,
        settlingDelay: TimeInterval = SendGate.defaultSettlingDelay,
        gate: ConversationOpenerGate = ConversationOpenerGate()
    ) {
        self.connection = connection
        self.policyStore = policyStore
        self.settingsStore = settingsStore
        self.actionLog = actionLog
        self.generator = generator
        self.sendStore = sendStore
        self.summaryStore = summaryStore
        self.settlingDelay = settlingDelay
        self.gate = gate
    }

    @discardableResult
    public func callAsFunction(now: Date = Date()) async -> [AgentAction] {
        guard (try? await policyStore.anyRoomOpensConversations()) == true else { return [] }
        guard let globalEnabled = try? await settingsStore.globalResponsesEnabled(), globalEnabled else {
            return []
        }
        guard case let .connected(account) = await connection.status() else { return [] }

        let style = (try? await settingsStore.responseStyle()) ?? ResponseStyle()
        let rooms = (try? await connection.chatRooms()) ?? []

        var recorded: [AgentAction] = []
        for room in rooms {
            guard let policy = try? await policyStore.policy(
                for: room,
                accountFingerprint: account.fingerprint
            ),
                policy.conversationOpener.isOn
            else {
                continue
            }
            if let action = await consider(room: room, policy: policy, account: account, style: style, now: now) {
                recorded.append(action)
            }
        }
        return recorded
    }

    /// Nil whenever the room is not due, which is nearly always. None of those
    /// holds reach the timeline: a room waiting out its interval produces one on
    /// every sweep for hours, which is the same flood the batching hold and the
    /// out-of-hours hold are deliberately kept out of the record for.
    private func consider(
        room: ChatRoom,
        policy: RoomPolicy,
        account: AccountProfile,
        style: ResponseStyle,
        now: Date
    ) async -> AgentAction? {
        guard let messages = try? await connection.recentMessages(
            in: room,
            limit: ConversationWindow.messageLimit
        ) else {
            return nil
        }

        let lastJudgementAt = try? await actionLog.lastJudgementDate(
            chatRoomID: room.id,
            accountFingerprint: account.fingerprint
        )

        // ②연속 횟수: how many times we have opened since the other side last spoke.
        // Counted from their last message, so a single reply from anyone moves that
        // boundary forward and the run reads as reset — the same instant the gate
        // measures the limit against. A room where the other side has never spoken
        // (only our own words, or an empty history) has no such boundary, and the
        // run is simply zero.
        let opensSinceTheyLastSpoke: Int
        if let theirLastMessageAt = messages.last(where: { !$0.isFromMe })?.sentAt {
            opensSinceTheyLastSpoke = (try? await actionLog.openerCount(
                chatRoomID: room.id,
                accountFingerprint: account.fingerprint,
                since: theirLastMessageAt
            )) ?? 0
        } else {
            opensSinceTheyLastSpoke = 0
        }

        let verdict = gate.evaluate(
            ConversationOpenerRequest(
                room: room,
                policy: policy,
                globalResponsesEnabled: true,
                accountVerified: true,
                recentMessages: messages,
                lastJudgementAt: lastJudgementAt ?? nil,
                opensSinceTheyLastSpoke: opensSinceTheyLastSpoke,
                now: now
            )
        )
        guard verdict == .open else { return nil }

        return await open(
            room: room,
            policy: policy,
            account: account,
            messages: messages,
            style: style,
            now: now
        )
    }
}
