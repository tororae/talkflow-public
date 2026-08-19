import Foundation
import TalkFlowDomain

/// One refresh of one room's note: read what has happened since, ask the model to
/// fold it into what the note already says, store the answer.
///
/// Shared by the sweep and by the button on the room screen, because the two
/// differ only in who decided the room was due. Written once so the button cannot
/// drift into producing a differently-shaped note than the sweep does.
struct ConversationSummaryRefresher: Sendable {
    let connection: any KakaoConnection
    let summaryStore: any ConversationSummaryStore
    let writer: any ConversationSummaryWriter
    /// 사람 기억 rides this refresh rather than a call of its own, so the three it
    /// needs live here: the notes to fold into, the switch that says whether this
    /// room takes part, and the log that says who has actually been answered.
    let personNotes: (any PersonNoteStore)?
    let policyStore: (any RoomPolicyStore)?
    let actionLog: (any AgentActionLog)?

    /// Nil when there is nothing to fold in, when the room cannot be read, or when
    /// the model call failed.
    ///
    /// Nothing here reaches the timeline. A row in `agent_actions` carrying a
    /// context count is what marks a model call, and `lastJudgementDate` paces
    /// 판단 주기 off exactly those rows — a summary recorded there would push every
    /// batching room's cycle around for a call that answered nobody. The room
    /// screen shows the refresh time instead, next to the note it produced.
    func refresh(
        room: ChatRoom,
        accountFingerprint: String,
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
        return await write(room: room, accountFingerprint: accountFingerprint, previous: previous, newMessages: fresh, now: now)
    }

    /// Split out so the sweep, which has already counted the new messages to
    /// decide whether the room was due, does not read the room a second time.
    func write(
        room: ChatRoom,
        accountFingerprint: String,
        previous: ConversationSummary?,
        newMessages: [ChatMessage],
        now: Date
    ) async -> ConversationSummary? {
        let window = ConversationWindow.bounded(
            newMessages,
            messageLimit: ConversationSummaryRefresh.historyLimit,
            characterBudget: ConversationSummaryRefresh.characterBudget
        )
        guard let newest = window.messages.last else { return nil }

        let known = await eligiblePeople(
            in: room,
            accountFingerprint: accountFingerprint,
            speaking: window.messages
        )
        let request = ConversationSummaryRequest(
            room: room,
            previous: previous,
            newMessages: window.messages,
            omittedMessageCount: window.omittedCount,
            people: known
        )
        guard let result = try? await writer.writeSummary(request) else { return nil }

        await savePeople(result.people, seenIn: window.messages, known: known, now: now)

        let summary = ConversationSummary(
            accountFingerprint: accountFingerprint,
            chatRoomID: room.id,
            text: result.summary,
            updatedAt: now,
            // Carried, not cleared. A pinned note never reaches here — both the
            // sweep and the manual button check it first — so the only way this
            // line runs on a pinned room is a future call site that forgot to, and
            // it should not be the thing that silently unpins somebody's note.
            isPinned: previous?.isPinned ?? false,
            coveredThroughMessageID: newest.id,
            coveredMessageCount: (previous?.coveredMessageCount ?? 0) + window.messages.count
        )
        // An empty answer is not a summary of a quiet room; it is a value that
        // would erase a good note. The old one stands and the room is asked again
        // on the next sweep.
        guard summary.isUsable else { return nil }

        try? await summaryStore.save(summary)
        return summary
    }
}
