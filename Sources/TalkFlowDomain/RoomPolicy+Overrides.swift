import Foundation

/// What a room takes from the global settings, and what it replaces.
///
/// Two settings work this way now — 답변 조건 and 응답 스타일 — and both resolve
/// here so a third cannot invent a different meaning for nil. In both, nil is
/// "follow 설정", and that is what every room configured before overrides existed
/// holds.
public extension RoomPolicy {
    /// The style this room answers in.
    ///
    /// The keywords always come from the global style, whatever the room does,
    /// because they are not style: 이 방이 답하는 말 is its own setting with its own
    /// list on the room screen, and a 말투 override may not quietly change which
    /// messages the room answers to.
    func responseStyle(global: ResponseStyle) -> ResponseStyle {
        guard var own = responseStyleOverride else { return global }
        own.responseKeywords = global.responseKeywords
        return own
    }

    /// The 답변 조건 this room judges by.
    ///
    /// An override that is empty is still an override. "이 방에서는 조건 없이 다
    /// 판단해" is a thing to want in a room where the global condition is too
    /// narrow, and reading a blank as "follow the global" would make it
    /// impossible to say.
    func answeringCondition(global: AnsweringCondition) -> AnsweringCondition {
        answeringConditionOverride ?? global
    }

    /// Whether this room answers in a style of its own. The room screen asks it
    /// of the checkbox, and the summary asks it to say which style is in force.
    var usesOwnResponseStyle: Bool { responseStyleOverride != nil }

    /// Whether this room judges by a condition of its own.
    var usesOwnAnsweringCondition: Bool { answeringConditionOverride != nil }
}
