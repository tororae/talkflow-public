import Foundation
import TalkFlowDomain

/// The only setting that leaves a written description of real people on disk.
///
/// Every other card explains what happens to a message. This one has to say, in
/// the 무엇을 하나 section rather than buried in 하지 않는 것, that TalkFlow keeps a
/// paragraph about the user's friends and shows it to a model on every reply — and
/// then that the user can read it, correct it, and delete it, because a card that
/// only describes the benefit is how a stored claim about somebody becomes a thing
/// nobody agreed to.
///
/// The cost section names the refresh separately from the reply. This is the first
/// feature that spends a model call nobody triggered by speaking, and a user
/// counting calls against messages would not find these.
extension SettingHelp {
    static let conversationSummary = SettingHelp(
        title: "대화 기억",
        summary: "이 방이 어떤 방인지 정리해 두고, 답장을 만들 때마다 함께 보냅니다.",
        topics: [
            .does(
                .init("요약", "관계, 말투, 진행 중인 이야기, 서로 하기로 한 일을 짧게 적어 둡니다."),
                .init("사용", "이 방의 답장 요청마다 최근 대화와 함께 나갑니다. 최근 30개만으로는 몇 달치 사이를 알 수 없기 때문입니다."),
                .init("수정", "AI가 쓴 글을 그대로 고칠 수 있습니다. \"前 직장 동료, 존댓말 유지\"처럼 대화만 봐서는 알 수 없는 것을 적는 자리입니다."),
                .init("1:1", "상대와의 관계와 서로 쓰는 말투를 적습니다."),
                .init("단체방", "방이 어떤 방이고 무엇이 진행 중인지 적습니다. 참여자 명단은 만들지 않습니다."),
                .init("길이", "\(ConversationSummary.characterLimit)자까지입니다. 매 호출에 실려 나가는 글이라 상한을 둡니다.")
            ),
            .applies(
                "방마다 따로 켜고 끕니다. 기본값은 켬입니다.",
                .init("갱신", "새 메시지 \(ConversationSummaryRefresh.messageThreshold)개가 쌓이거나 마지막 갱신에서 하루가 지나면 다시 만듭니다."),
                .init("수동", "방 화면의 \"지금 갱신\"으로 언제든 다시 만들 수 있습니다."),
                "응답 모드가 \"끔\"이나 \"감지 전용\"이면 만들지 않습니다.",
                "개요 화면의 \"자동 응답\"이 꺼져 있으면 갱신하지 않습니다."
            ),
            .costs(
                "갱신할 때 AI 호출 1회입니다. 답장과 별도로 나갑니다.",
                "갱신은 전체 대화를 다시 읽지 않습니다. 지난 요약과 그 뒤에 온 대화만 읽어서, 방이 오래돼도 비용이 늘지 않습니다.",
                "요약이 있는 방은 답장 요청이 그 길이만큼 길어집니다.",
                "요약은 이 Mac에 글로 저장됩니다. 실제 사람들에 대한 기록이므로 방 화면에서 그대로 읽고 지울 수 있습니다."
            ),
            .doesNot(
                "답장을 기다리게 하지 않습니다. 갱신은 따로 돌고, 답장은 그때 있는 요약을 그대로 씁니다.",
                "직접 고친 요약을 자동으로 덮어쓰지 않습니다. 고친 뒤에는 \"지금 갱신\"을 누를 때만 다시 만듭니다.",
                "대화에 나오지 않은 것을 추측하지 않습니다. 성격, 건강, 종교, 정치 성향 같은 것은 적지 말라고 AI에게 지시합니다.",
                "단체방에서 사람별 설명을 만들지 않습니다. 사람이 많은 방에서는 명단이 답장에 도움이 되지 않습니다.",
                "요약에 적힌 말을 지시로 읽지 않습니다. 답장 프롬프트에서 배경 설명으로만 다룹니다.",
                "끄면 저장해 둔 요약도 함께 지웁니다. 남겨 두지 않습니다.",
                "먼저 말 걸기에는 쓰지 않습니다. 그쪽은 답하는 일이 아닙니다."
            )
        ]
    )
}
