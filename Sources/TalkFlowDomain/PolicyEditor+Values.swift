import Foundation

/// The value parsers behind `PolicyEditor`'s table — text as an operator types it
/// into the one typed value a field holds, or nil so the field refuses.
///
/// Split out of `PolicyEditor.swift` only for size: the table there names these,
/// each of them is the single place its field's synonyms are listed, and a parse
/// returning nil is what becomes 「그런 값이 아니에요」 with the field's `allowed`
/// echoed back.
extension PolicyEditor {
    // MARK: - value → typed

    static func responseMode(_ v: String) -> ResponseMode? {
        switch v {
        case "끔", "꺼짐", "off": .off
        case "감지", "감지전용", "감지 전용": .detectOnly
        case "멘션", "멘션만", "멘션에만": .mentionOnly
        case "자동", "자동응답": .automatic
        default: nil
        }
    }

    static func deliveryMode(_ v: String) -> DeliveryMode? {
        switch v {
        case "초안", "초안만": .draftOnly
        case "유휴", "유휴자동", "유휴상태": .autoSendWhenIdle
        case "상시", "상시전송": .always
        default: nil
        }
    }

    static func opener(_ v: String) -> ConversationOpener? {
        switch v {
        case "끔", "꺼짐", "off": .off
        case "초안", "초안만": .draftOnly
        case "전송", "전송까지": .delivers
        default: nil
        }
    }

    static func repeatTopic(_ v: String) -> OpenerRepeatTopic? {
        switch v {
        case "이어가기", "이어", "유지": .carryOn
        case "새주제", "새", "새로": .fresh
        default: nil
        }
    }

    static func bool(_ v: String) -> Bool? {
        switch v {
        case "켬", "켜기", "켜짐", "on", "true", "1", "o", "O": true
        case "끔", "끄기", "꺼짐", "off", "false", "0", "x", "X": false
        default: nil
        }
    }

    /// A percentage, with or without the sign the console prints it with, refused
    /// outside 0~100 rather than clamped: a typo landing on a different number than
    /// the one typed is worse than being asked to retype it.
    static func percent(_ v: String) -> InterjectionChance? {
        let digits = v.replacingOccurrences(of: "%", with: "")
        guard let percent = Int(digits), (0...100).contains(percent) else { return nil }
        return InterjectionChance(percent: percent)
    }

    /// A repeat count, refused outside 0~99 the same way a percentage is.
    static func repeatLimit(_ v: String) -> Int? {
        guard let n = Int(v), (0...99).contains(n) else { return nil }
        return n
    }

    /// `없음`/`0`/`끔` → no minimum; otherwise an integer with a 초·분·시간 suffix, and
    /// a bare number is read as seconds. Anything else is nil so the field refuses.
    static func duration(_ v: String) -> TimeInterval? {
        let s = v.replacingOccurrences(of: " ", with: "")
        if s == "없음" || s == "0" || s == "끔" { return 0 }
        if let n = Int(s), n >= 0 { return TimeInterval(n) }
        for (suffix, seconds) in [("시간", 3600.0), ("분", 60.0), ("초", 1.0)] {
            if s.hasSuffix(suffix), let n = Int(s.dropLast(suffix.count)), n >= 0 {
                return TimeInterval(n) * seconds
            }
        }
        return nil
    }

    /// `항상`/`제한없음`/`없음` → unlimited; `HH:MM-HH:MM` (either dash) → a window.
    /// A time outside 00:00–23:59 is nil; a window whose end precedes its start —
    /// 22:00-02:00 — is left to `ReplyActiveHours`, which runs it to the next
    /// morning rather than reading it as empty.
    static func activeHours(_ v: String) -> ReplyActiveHours? {
        let s = v.replacingOccurrences(of: " ", with: "")
        if s == "항상" || s == "제한없음" || s == "없음" { return .always }
        let parts = s.split(whereSeparator: { $0 == "-" || $0 == "~" }).map(String.init)
        guard parts.count == 2, let start = clock(parts[0]), let end = clock(parts[1]) else { return nil }
        return ReplyActiveHours(isLimited: true, startMinute: start, endMinute: end)
    }

    static func clock(_ v: String) -> Int? {
        let hm = v.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard hm.count == 2, let h = Int(hm[0]), let m = Int(hm[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return h * 60 + m
    }

    /// `즉시`/`0` → immediate; otherwise a duration or count, optionally a `~` range.
    /// `개`(messages) is admitted only where the field counts messages (판단주기), and
    /// a range must not mix units — `5분~10개` is nil, not a cycle wearing two names.
    static func judgement(_ v: String, allowMessages: Bool) -> JudgementInterval? {
        let s = v.replacingOccurrences(of: " ", with: "")
        if s == "즉시" || s == "0" { return .immediate }
        let parts = s.split(separator: "~", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard let lowText = parts.first, let low = judgementAmount(lowText, allowMessages: allowMessages) else { return nil }
        guard parts.count == 2 else {
            return JudgementInterval(measure: low.measure, shortest: low.value, longest: low.value)
        }
        guard let high = judgementAmount(parts[1], allowMessages: allowMessages), high.measure == low.measure else {
            return nil
        }
        return JudgementInterval(measure: low.measure, shortest: low.value, longest: high.value)
    }

    /// One end of a 판단주기: `10개`(messages), or `30초`/`5분`/`2시간`(a bare number is
    /// seconds). `개` is refused where the field does not count messages.
    static func judgementAmount(_ s: String, allowMessages: Bool) -> (value: Double, measure: JudgementInterval.Measure)? {
        if s.hasSuffix("개") {
            guard allowMessages, let n = Int(s.dropLast(1)), n >= 0 else { return nil }
            return (Double(n), .messages)
        }
        for (suffix, seconds) in [("시간", 3600.0), ("분", 60.0), ("초", 1.0)] {
            if s.hasSuffix(suffix), let n = Int(s.dropLast(suffix.count)), n >= 0 {
                return (Double(n) * seconds, .seconds)
            }
        }
        if let n = Int(s), n >= 0 { return (Double(n), .seconds) }
        return nil
    }
}
