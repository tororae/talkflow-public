import Foundation
import TalkFlowDomain

/// The one setting in this app that makes it speak without being spoken to.
///
/// Every other card explains what happens to a message somebody sent. This one has
/// to say, before anything else, that turning it on means words appearing in a
/// room under the user's name with nobody having asked for them — and then say
/// every condition that still has to hold, because a user who reads "먼저 말 걸기"
/// and expects a bot chatting all day has misread it in the safe direction only by
/// luck.
extension SettingHelp {
    static let conversationOpener = SettingHelp(
        title: "먼저 말 걸기",
        summary: "아무도 말을 걸지 않아도 TalkFlow가 내 이름으로 먼저 말을 겁니다.",
        topics: [
            .does(
                .init("꺼짐", "기본값입니다. 아무도 부르지 않으면 이 방에서 아무 말도 하지 않습니다."),
                .init("초안만", "먼저 걸 말을 만들어 두고, 활동 화면에서 사람이 눌러야 나갑니다."),
                .init("전송까지", "만든 말이 사람 확인 없이 이 방의 전송 방식대로 나갑니다."),
                .init("주제", "그 방의 최근 대화에서 이어질 만한 이야기를 AI가 고릅니다."),
                .init("주기", "\(Int(JudgementIntervalInput.conversationOpener.time.lowest / 60))분부터 \(Int(JudgementIntervalInput.conversationOpener.time.highest / 3600))시간까지 범위로 적습니다. 매번 그 사이에서 달라집니다.")
            ),
            .applies(
                "이 방에만 적용되고, 방마다 따로 켭니다.",
                .init("조용할 때만", "마지막 메시지가 \(Int(ConversationOpenerGate.defaultQuietPeriod / 60))분 넘게 지났을 때만 겁니다. 대화 중에는 끼어들지 않습니다."),
                "답변 활성화 시간 안에서만 겁니다. 새벽에 먼저 말을 걸지 않습니다.",
                "개요 화면의 \"자동 응답\"이 꺼져 있으면 아무 일도 하지 않습니다.",
                "응답 모드가 \"끔\"이나 \"감지 전용\"이면 켜도 아무 일도 하지 않습니다."
            ),
            .costs(
                "주기마다 AI 호출 1회입니다. 답할 말이 없다고 나와도 그 호출은 나갑니다.",
                "보낸 메시지는 되돌릴 수 없습니다. 답장과 달리 상대가 기다린 말도 아닙니다.",
                "이 방의 최근 대화가 AI 제공자로 나갑니다. 답장을 만들 때와 같은 범위입니다."
            ),
            .doesNot(
                "켜도 매 주기마다 말을 걸지는 않습니다. 꺼낼 이야기가 없으면 AI가 그냥 넘깁니다.",
                "이 방이 자동 전송이어도 \"초안만\"이 기본값입니다. 답을 대신 하는 것과 먼저 말을 거는 것은 다른 허락입니다.",
                "\"전송까지\"로 두어도 전송 방식이 \"초안만\"이면 나가지 않습니다.",
                "기다리는 동안 방에서 누가 말하면 만들어 둔 말을 취소합니다.",
                "차례를 기다리는 동안의 보류는 활동 기록에 남기지 않습니다.",
                "인사나 안부를 던지지 않습니다. 최근 대화에서 이어지지 않는 말은 만들지 말라고 AI에게 지시합니다."
            )
        ]
    )
}
