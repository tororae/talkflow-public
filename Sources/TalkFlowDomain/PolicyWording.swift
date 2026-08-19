import Foundation

/// The words a room policy's values read as — one copy each.
///
/// Three things print the same stored value and have to call it the same thing:
/// `!방 <N>`'s settings card (`AdminCommandResponder`), `!세팅`'s field view
/// (`PolicyEditor`), and the bound a range field quotes when it refuses a number
/// (`JudgementIntervalInput`). Each carried its own formatter, and they drifted:
/// 집중시간 read 「꺼짐」 on `!방 3` and 「끔」 on `!세팅 3 집중시간` for the same
/// `false`, so the console answered two words to one question. The seconds → 시간/분/초
/// reading existed four times: twice answering 「없음」 for zero and twice not, which
/// is why it is two functions here — `span` for a reading something appends to,
/// `duration` for a field that stands alone. Collapsing them into one is what makes
/// 「없음마다」, and that is not a cadence.
///
/// In the domain rather than beside the console because that is where the values
/// are, and where their other readings already live — `ResponseMode.title`,
/// `JudgementInterval.summary`, `ReplyActiveHours.summary`. Pure: no file, no
/// screen, no clock, nothing of Foundation but the `TimeInterval` typealias.
public enum PolicyWording {
    /// A toggle field's value.
    ///
    /// 「끔」, not 「꺼짐」, because `PolicyEditor.allowed` advertises 「켬·끔」 as what
    /// every toggle field accepts — and `PolicyEditor.bool` reads back 켬/켜기/켜짐
    /// and 끔/끄기/꺼짐 — so the console echoes the word it asked for rather than a
    /// synonym the operator would then have to guess was the same state.
    public static func onOff(_ on: Bool) -> String { on ? "켬" : "끔" }

    /// A span of seconds in the largest unit that keeps it whole. "7200초" is a
    /// number the reader has to do arithmetic on.
    ///
    /// Always a number and a unit, including for zero, because this is the reading
    /// something else glues a suffix onto — 「5분마다」, 「5분보다 짧게는」. A span that
    /// answered 「없음」 here would compose into 「없음마다」.
    public static func span(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded())
        if whole % 3600 == 0 { return "\(whole / 3600)시간" }
        if whole % 60 == 0 { return "\(whole / 60)분" }
        return "\(whole)초"
    }

    /// A whole field's value, where the span stands on its own with nothing glued
    /// to it: 최소 응답 간격 is a bare `TimeInterval` with no `summary` of its own to
    /// ask, and its zero is a state rather than a length — no minimum, not a wait of
    /// 「0초」. Anything that reads as a fragment wants `span` instead.
    public static func duration(_ seconds: TimeInterval) -> String {
        Int(seconds.rounded()) <= 0 ? "없음" : span(seconds)
    }
}
