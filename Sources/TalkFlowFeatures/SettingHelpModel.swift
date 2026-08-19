import Foundation
import TalkFlowDomain

/// AI 모델 — the setting that decides which model writes every answer.
///
/// It needs a card more than most, because until it existed the answer to "which
/// model is this?" was a file TalkFlow never mentioned. The card has to say two
/// things a user cannot find out any other way: that 선택 안 함 hands the decision
/// to Codex CLI's own config, and that nothing here touches that config back.
extension SettingHelp {
    /// The option lines are built from `AIModel.catalog` rather than typed out.
    /// A card that repeats a list by hand goes on naming a model long after the
    /// code has dropped it, and this list moves whenever the provider's does.
    static let aiModel = SettingHelp(
        title: "AI 모델",
        summary: "어느 모델이 답장을 쓸지 고릅니다.",
        topics: [
            Topic(
                question: .does,
                lines: [
                    .init("선택 안 함", "TalkFlow가 모델을 지정하지 않고, Codex CLI에 설정된 모델을 그대로 씁니다. 기본값입니다.")
                ] + AIModel.catalog.map { .init($0.name, $0.summary) }
            ),
            .applies(
                "모든 채팅방에 적용됩니다. 방마다 다른 모델을 고를 수는 없습니다.",
                "답장과 채팅방 요약이 같은 모델을 씁니다.",
                "고르는 즉시 저장되고 다음 호출부터 적용됩니다. 저장 버튼을 누를 필요가 없습니다."
            ),
            .costs(
                "좋은 모델일수록 답장 한 번이 느리고 ChatGPT 사용량을 많이 씁니다.",
                "AI 호출 수는 달라지지 않습니다. 한 번의 호출이 어느 모델로 가는지만 달라집니다.",
                "고른 모델이 일시적으로 붐비면 그 호출은 실패합니다. 활동 화면에 이유가 남습니다."
            ),
            .doesNot(
                "Codex CLI의 설정 파일을 고치지 않습니다. 그 파일은 터미널에서 하는 다른 작업의 것입니다.",
                "추론 강도는 바꾸지 않습니다. codex exec에 그 옵션이 없어 Codex 설정이 정합니다.",
                "얼마나 자주 답할지는 바뀌지 않습니다. 그것은 끼어들기 확률과 판단 주기입니다.",
                "무엇에 답할지도 바뀌지 않습니다. 그것은 답변 조건입니다."
            )
        ]
    )
}
