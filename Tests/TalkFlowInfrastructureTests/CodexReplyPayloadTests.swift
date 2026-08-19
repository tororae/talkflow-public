import Foundation
import Testing
import TalkFlowDomain
@testable import TalkFlowInfrastructure

/// The schema is what the answer is validated against, so a field it does not
/// list cannot come back at all — `additionalProperties` is false. A reason the
/// prompt asks for and the schema forbids would be silently dropped, which is
/// the one failure this pair can have.
@Test
func theSchemaLetsTheModelReturnAReasonOrNull() throws {
    let schema = try #require(
        try JSONSerialization.jsonObject(
            with: Data(CodexReplyGenerator.responseSchema.utf8)
        ) as? [String: Any]
    )
    let properties = try #require(schema["properties"] as? [String: Any])
    let reason = try #require(properties["decline_reason"] as? [String: Any])
    let required = try #require(schema["required"] as? [String])

    #expect(reason["type"] as? [String] == ["string", "null"])
    #expect(required.contains("decline_reason"))
}

@Test
func aDeclineWithAReasonDecodesIntoTheDraft() throws {
    let json = """
    {
      "should_reply": false,
      "reply_mode": "spontaneous",
      "confidence": "low",
      "reply_text": null,
      "decline_reason": "서로 안부만 묻는 중이라 낄 자리가 없음"
    }
    """

    let draft = try #require(decode(json)?.draft)

    #expect(draft.usableText == nil)
    #expect(draft.usableDeclineReason == "서로 안부만 묻는 중이라 낄 자리가 없음")
}

/// The key is required of the model, but a response that predates it — or a
/// provider that answers in the old shape — still has to parse. Losing the whole
/// judgement over a missing explanation would trade a reply for a sentence.
@Test
func aResponseWithoutTheNewFieldStillDecodes() throws {
    let json = """
    {
      "should_reply": true,
      "reply_mode": "direct_question",
      "confidence": "high",
      "reply_text": "네 그때 봬요"
    }
    """

    let draft = try #require(decode(json)?.draft)

    #expect(draft.usableText == "네 그때 봬요")
    #expect(draft.usableDeclineReason == nil)
}

private func decode(_ json: String) -> CodexReplyPayload? {
    try? JSONDecoder().decode(CodexReplyPayload.self, from: Data(json.utf8))
}
