import TalkFlowApplication
import TalkFlowDomain

/// What one room's screen asks on demand: who has called it, what its name
/// reads as, and when it next judges. None of it is loaded with the list —
/// it is slow, it is per-room, and it leaves no trace in the timeline.
///
/// All three share the `inspectingRoomID` guard, which is why they are one
/// file: opening another room mid-read must not land the first room's answer
/// in the second.
@MainActor
extension ChatRoomListModel {
    /// Reads what the room's own screen has to explain about its silence: whether
    /// anybody has used the words it answers to, and when it next judges if it is
    /// accumulating. Neither leaves a trace in the timeline, so both are read on
    /// demand where the settings are.
    public func inspectRecentCalls(for entry: ChatRoomPolicy) async {
        // Opening another room clears the refusals with it: a complaint about a
        // word or a condition typed in the last room means nothing beside this
        // one's settings.
        inspectingRoomID = entry.id
        keywordIssue = nil
        conditionIssue = nil
        recentCalls = nil
        judgementCycle = nil
        // Guarded like RoomSummaryModel.load: this reads the archive, which is
        // slow, and opening another room mid-read must not land the first room's
        // calls in the second room's section.
        let calls = await inspectCalls(room: entry.room, signs: callSigns(for: entry))
        guard inspectingRoomID == entry.id else { return }
        recentCalls = calls
        await refreshJudgementCycle(for: entry)
    }

    /// 이름 다시 읽기. Throws away the remembered name and reads the archive again.
    ///
    /// A rename in KakaoTalk used to need the app restarted: the account name was
    /// resolved once per launch and held with no way to clear it, which made the
    /// only event it changes for the one event it could not see.
    public func rereadNickname(for entry: ChatRoomPolicy) async {
        inspectingRoomID = entry.id
        let calls = await inspectCalls.rereadingNickname(
            room: entry.room,
            signs: callSigns(for: entry)
        )
        guard inspectingRoomID == entry.id else { return }
        recentCalls = calls
    }

    func refreshJudgementCycle(for entry: ChatRoomPolicy) async {
        guard case let .loaded(board) = state else { return }
        let cycle = await inspectCycle(
            room: entry.room,
            policy: entry.policy,
            accountFingerprint: board.accountFingerprint
        )
        guard inspectingRoomID == entry.id else { return }
        judgementCycle = cycle
    }
}
