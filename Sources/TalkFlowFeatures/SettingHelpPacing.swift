import Foundation
import TalkFlowDomain

/// The three settings that bound how often a room speaks.
///
/// Two of them mean overlapping things, so only one is ever in force, and the
/// cards say which. The difference that matters is what happens to the messages
/// they pass over: 판단 주기 keeps them and 최소 응답 간격 does not — a call that
/// arrives inside the cooldown is skipped and never looked at again.
///
/// 판단 주기 itself is counted one of two ways, and its card has to name the trade
/// rather than list two options: a clock keeps a slow room answering almost every
/// message, and a count keeps a quiet room waiting. Neither is the better one,
/// which is exactly why the choice is the user's.
///
/// 끼어들기 확률 is the other lever that spends less, and its card is beside the
/// settings that decide whether there is an answer at all. It belongs there
/// because it answers a different question — how often to *ask*, rather than when
/// — but a user picking one of the two needs to see the other named, so each card
/// names it.
extension SettingHelp {
    static let judgementInterval = SettingHelp(
        title: "판단 주기",
        summary: "AI에게 언제 물어볼지 정합니다. 시간으로도, 대화 수로도 셉니다.",
        topics: [
            .does(
                .init("즉시", "새 메시지가 올 때마다 판단합니다. 기본값이며, 앱이 알아서 바꾸지 않습니다."),
                .init("주기마다", "그 사이 온 메시지를 모아 두었다가 주기가 끝날 때 한 번만 묻습니다."),
                .init("초·분", "시간으로 셉니다. \(Int(JudgementIntervalInput.judgement.time.lowest))초부터 \(Int(JudgementIntervalInput.judgement.time.highest / 60))분까지 적습니다."),
                .init("개", "다른 사람의 메시지 수로 셉니다. \(messageFloor)개부터 \(messageCeiling)개까지 적습니다."),
                .init("범위", "최소와 최대를 다르게 적으면 주기마다 그 사이에서 값이 달라집니다. 최대를 비우면 고정입니다.")
            ),
            .applies(
                "이 방에만 적용됩니다.",
                "단위 하나만 적용됩니다. 시간과 개수를 함께 걸 수는 없고, 지금 무엇으로 세는지는 숫자 옆의 단위입니다.",
                "주기를 켜면 최소 응답 간격은 잠기고 적용되지 않습니다. 둘 다 \"얼마나 자주 답하나\"를 정하기 때문입니다.",
                "주기의 기준은 마지막으로 답한 시각이 아니라 마지막으로 AI를 부른 시각입니다.",
                "끼어들기 확률과는 함께 적용됩니다. 확률로 걸러진 메시지는 모으지도 않습니다."
            ),
            .costs(
                .init("즉시", "대체로 메시지 1개에 AI 호출 1회입니다. 말이 많은 방일수록 그대로 늘어납니다."),
                .init("주기마다", "주기당 호출 1회입니다. 대신 답이 최대 그 주기만큼 늦습니다."),
                .init("시간", "방이 느리면 주기마다 메시지 한두 개만 모입니다. 결국 거의 모든 글에 답하게 됩니다."),
                .init("개수", "방이 느리면 그만큼 오래 기다립니다. 조용한 방에서는 몇 시간이 될 수도 있습니다."),
                .init("끼어들기 확률", "그쪽도 호출을 줄입니다. 다만 확률은 메시지를 버리고, 주기는 모아 두었다가 한 번에 봅니다.")
            ),
            .doesNot(
                "내가 보낸 말은 개수에 넣지 않습니다. 내가 말하는 중에 답이 앞당겨지지 않습니다.",
                "범위로 두어도 주기 중간에 값이 바뀌지 않습니다. 주기가 시작할 때 정해지고 그 주기 동안 그대로입니다.",
                "주기 중에 메시지가 와도 시간 주기가 미뤄지지 않습니다. 끝나는 시각은 방 화면에 적혀 있습니다.",
                "주기가 끝나는 순간 스스로 판단하지 않습니다. 그 뒤 새 메시지가 올 때 모아 둔 것을 한 번에 봅니다.",
                "모은 메시지를 버리지 않습니다. 주기가 끝나면 그 사이 온 것을 전부 놓고 판단하므로, 주기 초반에 부른 사람도 남아 있습니다.",
                "모은 대화가 길어지면 오래된 것부터 빼고 몇 개를 뺐는지 AI에게 알립니다. 뺀 부분을 요약해서 넣지는 않습니다.",
                "모으는 동안의 보류는 활동 기록에 남기지 않습니다."
            )
        ]
    )

    /// Read off the bounds rather than typed again here, like the two numbers
    /// above them. A card that repeats a limit by hand goes on saying the old one
    /// after the field has moved on, and this card is the reason the user thinks
    /// they know what the field takes.
    private static var messageFloor: Int {
        Int(JudgementIntervalInput.judgement.messages?.lowest ?? 0)
    }

    private static var messageCeiling: Int {
        Int(JudgementIntervalInput.judgement.messages?.highest ?? 0)
    }

    static let minimumInterval = SettingHelp(
        title: "최소 응답 간격",
        summary: "한 번 답한 뒤 이 시간 동안은 이 방에서 판단하지 않습니다.",
        topics: [
            .does(
                "마지막으로 답한 시각부터 잽니다.",
                "그 사이에 온 메시지는 판단하지 않고 건너뜁니다."
            ),
            .applies("판단 주기가 \"즉시\"일 때만 적용됩니다. 주기를 켜면 이 값은 잠기고 무시됩니다."),
            .costs("건너뛴 메시지에는 AI 호출이 나가지 않습니다. 대신 그 메시지의 답도 없습니다."),
            .doesNot(
                "건너뛴 메시지를 모아 두지 않습니다. 간격이 끝나도 그 메시지들은 다시 보지 않습니다.",
                "나를 부른 메시지도 예외가 아닙니다. 간격 안에 오면 그 부름은 그대로 지나갑니다. 부름을 놓치고 싶지 않으면 이 값 대신 판단 주기를 쓰는 편이 낫습니다.",
                "메시지 수집과 기록은 그대로 이어집니다."
            )
        ]
    )

    static let answersReplies = SettingHelp(
        title: "답장으로 부른 것도 인식",
        summary: "카카오톡 답장으로 내 메시지에 답한 것을 나를 부른 것으로 봅니다.",
        topics: [
            .does("최근 대화에서 누가 카카오톡 답장 기능으로 내가 보낸 메시지에 답했으면, 이름이나 키워드가 없어도 부름으로 봅니다."),
            .applies(
                "답장이 가리키는 원본이 최근 대화 안에 있을 때만 동작합니다. 며칠 전 메시지에 단 답장은 알아보지 못합니다.",
                "멘션에만 응답인 방에서도 동작합니다. 오히려 그런 방에 가장 필요합니다."
            ),
            .costs("부름이 늘어난 만큼 AI 호출도 늘어납니다."),
            .doesNot(
                "남의 메시지에 단 답장은 세지 않습니다. 내가 보낸 것에 달린 답장만입니다.",
                "답장 내용을 검사하지 않습니다. 답할지 말지는 그다음 판단입니다."
            )
        ]
    )
}
