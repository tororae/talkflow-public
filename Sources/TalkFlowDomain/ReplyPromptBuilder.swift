import Foundation

/// Turns a draft request into provider-agnostic prompt text.
///
/// Chat messages are untrusted input. They are fenced inside a single
/// `<conversation>` block, the fence is made unforgeable by neutralising any
/// closing tag a message tries to smuggle in, and the instructions say plainly
/// that nothing inside may change how TalkFlow behaves.
public struct ReplyPromptBuilder: Sendable {
    public init() {}

    public func prompt(for request: ReplyDraftRequest) -> String {
        """
        당신은 사용자를 대신해 카카오톡 답장 초안을 만드는 보조자입니다.

        \(rules(for: request))
        \(conditionSection(request.answeringCondition))
        \(PersonaStyleSection.rendered(request.style))
        \(summarySection(request.conversationSummary))
        \(senderSection(request.senderNote))
        \(omissionSection(request))
        \(conversationSection(request))
        \(ownRepliesSection(request))
        \(photoSection(request))
        \(webSearchSection(request))
        \(linkSection(request))

        마지막 메시지에 답할지 판단하고, 답한다면 사용자가 직접 쓴 것처럼 자연스러운 답장을 만드세요. 답장은 언어뿐 아니라 문체·형식까지 위 말투를 그대로 지키세요. 말투에 여러 단계 지시(예: 언어, 줄바꿈, 덧붙일 해석)가 담겨 있으면 그중 하나도 빠뜨리지 마세요. 말투가 언어를 따로 정하지 않았으면 대화에서 오간 언어로 답하세요.
        \(alreadySaidInstruction)
        \(declineReasonInstruction)
        \(followUpInstruction)
        """
    }
}
