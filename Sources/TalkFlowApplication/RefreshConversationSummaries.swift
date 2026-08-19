import Foundation
import TalkFlowDomain

/// Brings every room's standing note up to date, on its own schedule.
///
/// **Never on the reply path.** A refresh is its own model call, and a reply that
/// waited on one would answer a message minutes after it was sent for the sake of
/// context it could have had next time. So this does not hang off the sync stream
/// the way the reply pipeline does — that stream's handler runs to completion
/// before the next sync is delivered, and a summary call sitting in it would put
/// itself in front of the *next* room's reply. It rides the send queue's poll
/// instead, like the quiet-room sweep, with a cadence of its own.
///
/// Which means it runs for as long as the app is open, so it is built to be cheap
/// when there is nothing to do: every room's note is read in one query, and the
/// per-room work is an indexed archive read and two integer comparisons. The model
/// is only reached by a room that has actually accumulated something.
public struct RefreshConversationSummaries: Sendable {
    private let connection: any KakaoConnection
    private let policyStore: any RoomPolicyStore
    private let settingsStore: any AppSettingsStore
    private let summaryStore: any ConversationSummaryStore
    private let refresher: ConversationSummaryRefresher

    public init(
        connection: any KakaoConnection,
        policyStore: any RoomPolicyStore,
        settingsStore: any AppSettingsStore,
        summaryStore: any ConversationSummaryStore,
        writer: any ConversationSummaryWriter,
        personNotes: (any PersonNoteStore)? = nil,
        actionLog: (any AgentActionLog)? = nil
    ) {
        self.connection = connection
        self.policyStore = policyStore
        self.settingsStore = settingsStore
        self.summaryStore = summaryStore
        refresher = ConversationSummaryRefresher(
            connection: connection,
            summaryStore: summaryStore,
            writer: writer,
            personNotes: personNotes,
            policyStore: policyStore,
            actionLog: actionLog
        )
    }

    @discardableResult
    public func callAsFunction(now: Date = Date()) async -> [ConversationSummary] {
        // The global switch is a stop on spending, not only on speaking. A paused
        // app that kept paying for notes would be the emergency stop failing to
        // stop the one thing the user can see on the bill.
        guard let enabled = try? await settingsStore.globalResponsesEnabled(), enabled else {
            return []
        }
        guard case let .connected(account) = await connection.status() else { return [] }

        let stored = (try? await summaryStore.summaries(accountFingerprint: account.fingerprint)) ?? [:]
        let rooms = (try? await connection.chatRooms()) ?? []

        var written: [ConversationSummary] = []
        for room in rooms {
            guard let policy = try? await policyStore.policy(
                for: room,
                accountFingerprint: account.fingerprint
            ),
                policy.remembersConversation,
                // A room that answers nobody has no use for a note, and this app
                // does not write descriptions of people in rooms it was told to
                // stay out of.
                policy.answersMessages
            else {
                continue
            }

            if let summary = await consider(
                room: room,
                account: account,
                previous: stored[room.id],
                now: now
            ) {
                written.append(summary)
            }
        }
        return written
    }

    /// Nil whenever the room is not due, which is nearly always.
    private func consider(
        room: ChatRoom,
        account: AccountProfile,
        previous: ConversationSummary?,
        now: Date
    ) async -> ConversationSummary? {
        guard let messages = try? await connection.recentMessages(
            in: room,
            limit: ConversationSummaryRefresh.historyLimit
        ) else {
            return nil
        }

        let fresh = ConversationSummaryRefresh.newMessages(
            in: messages,
            after: previous?.coveredThroughMessageID
        )
        guard ConversationSummaryRefresh.isDue(previous, newMessageCount: fresh.count, now: now) else {
            return nil
        }

        return await refresher.write(
            room: room,
            accountFingerprint: account.fingerprint,
            previous: previous,
            newMessages: fresh,
            now: now
        )
    }
}
