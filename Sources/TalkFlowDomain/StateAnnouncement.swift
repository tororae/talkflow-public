import Foundation

/// The room being told that this account is about to be around, or about to stop
/// being around.
///
/// Four transitions and deliberately one feature. 집중 시간 and 답변 활성화 시간 are
/// unrelated settings on unrelated clocks — one is drawn per answer and runs for
/// minutes, the other is two times of day the user typed — but from inside the
/// room they produce the same two events: this account starts answering, this
/// account stops answering. The room cannot tell which setting moved, and has no
/// reason to care. Splitting this into four features would give one room four
/// voices for one fact and four places for the wording to drift.
///
/// What each case carries is the availability change and nothing else. The
/// obvious shortcut is a line per transition — 「일하러 감」, 「이제 잘게」 — and it
/// fails the second time it runs: the same excuse arriving in a 개발 팀 방 at two
/// in the afternoon and in a 가족 방 at midnight is a template, and a room that
/// reads one excuse twice knows what wrote it. The excuse is the model's to
/// invent out of the conversation in front of it. What this type supplies is the
/// fact the excuse has to be an excuse for.
public enum StateAnnouncement: String, CaseIterable, Equatable, Sendable {
    /// 집중 시간 began. The room is about to hear from this account far more often
    /// than it has been.
    case burningStarted
    /// 집중 시간 ended. The room goes back to the pace its own settings describe.
    case burningEnded
    /// 답변 활성화 시간 just opened, after a stretch where the room heard nothing.
    case activeHoursOpened
    /// 답변 활성화 시간 is about to close. Said before the silence rather than
    /// after it, because a line explaining an absence is only useful while
    /// somebody is still there to read it.
    case activeHoursClosed

    /// What actually changed, stated as availability rather than as a reason.
    ///
    /// This is the whole of what the prompt is told about the transition, and the
    /// bound is the point. Each sentence says when the room will and will not
    /// hear from this account and stops there; the moment one of them suggested a
    /// reason, every room would get that reason, which is the failure this
    /// feature exists to avoid.
    ///
    /// Written from the room's side, not the app's. 「집중 시간이 시작됐다」 is a
    /// setting changing state, and a model handed that sentence writes about the
    /// setting. 「한동안 이 방에 붙어 있게 됐다」 is a person, and a person is what
    /// the line has to sound like.
    public var situation: String {
        switch self {
        case .burningStarted:
            "사용자가 지금 막 이 대화방에 한동안 신경 쓸 짬이 생겼습니다."
        case .burningEnded:
            "사용자가 이 대화방에 내던 짬이 방금 끝나, 곧 다시 하던 일로 돌아갑니다."
        case .activeHoursOpened:
            "사용자가 이제 막 이 대화방을 다시 볼 수 있게 됐습니다. 그 전 한동안은 자리를 비우고 있었습니다."
        case .activeHoursClosed:
            "사용자가 곧 이 대화방에서 한동안 자리를 비웁니다."
        }
    }
}
