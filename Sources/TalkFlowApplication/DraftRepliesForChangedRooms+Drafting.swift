import Foundation
import TalkFlowDomain

/// The half of the pipeline that spends money and writes records: build the
/// request, ask the model, queue what came back, and leave a row either way.
///
/// Split from the deciding half because they fail differently. Everything here
/// has already been decided worth doing. One call and one record — whether to
/// ask a second time is `+FollowUp`'s question.
extension DraftRepliesForChangedRooms {
    struct Attempt {
        let outcome: Result<ReplyDraft, Error>
        let timeline: ActionTimeline

        /// A success that actually produced something to send. A model that came
        /// back empty is not usable, and a call that threw is not either — both are
        /// a miss the caller may retry.
        var hasUsableReply: Bool {
            if case let .success(reply) = outcome { return reply.usableText != nil }
            return false
        }
    }

    /// What is known about the person being answered, or nil.
    ///
    /// Only theirs. A room of eight people has eight notes and attaching all of
    /// them would send seven files to the provider to answer a message none of
    /// them sent, while pushing the conversation out of the prompt to do it.
    ///
    /// Gated on the room rather than on the note existing. A note is one per
    /// person and outlives any single room, so a person carried into a room where
    /// 사람 기억 is off would bring their file with them — and that room's user
    /// never agreed to it.
    func note(
        forSenderOf triggerMessageID: String,
        in messages: [ChatMessage],
        policy: RoomPolicy
    ) async -> PersonNote? {
        guard policy.remembersPeople, let personNotes else { return nil }
        guard let trigger = messages.first(where: { $0.id == triggerMessageID }),
              !trigger.isFromMe
        else {
            return nil
        }
        // The room the reply is being written for, so a reply here cannot be
        // informed by what this person said somewhere else.
        return try? await personNotes.note(
            inRoom: policy.chatRoomID,
            senderID: trigger.sender.id
        )
    }

    /// One model call, with the photos and the note it needs.
    ///
    /// Photos are extracted and deleted inside this call rather than around the
    /// whole exchange: a follow-up round asks again with a wider window, and
    /// pictures out of somebody's conversation do not sit on disk for the ten
    /// seconds in between.
    func ask(
        trigger: ReplyTrigger,
        triggerMessageID: String,
        room: ChatRoom,
        account: AccountProfile,
        policy: RoomPolicy,
        window: ConversationWindow.Bounded,
        style: ResponseStyle,
        condition: AnsweringCondition,
        searchStage: SearchStage,
        timeline: ActionTimeline
    ) async -> Attempt {
        var timeline = timeline
        let photos = await photos(for: window.messages, room: room, policy: policy)
        defer { photoSource?.discard(photos) }
        // No discard: a rendered page is text held in memory for this call, not a
        // file left on disk the way an extracted photo is.
        let links = await links(for: window.messages, room: room, policy: policy)

        let conversationSummary = await summary(for: room, account: account, policy: policy)
        let senderNote = await note(
            forSenderOf: triggerMessageID,
            in: window.messages,
            policy: policy
        )
        // Both reads that stand between the decision and the call are behind
        // this stamp — the photos above and the note just now. Neither is a model
        // call, and keeping them out of 모델 호출 is what stops a slow katok
        // extraction from being read as a slow provider.
        timeline.stamp(
            .contextPrepared,
            note: Self.contextNote(photoCount: photos.photos.count, linkCount: links.count)
        )

        let request = ReplyDraftRequest(
            room: room,
            trigger: trigger,
            triggerMessageID: triggerMessageID,
            recentMessages: window.messages,
            style: style,
            answeringCondition: condition,
            conversationSummary: conversationSummary,
            senderNote: senderNote,
            photos: photos.photos,
            links: links,
            omittedMessageCount: window.omittedCount,
            searchStage: searchStage
        )

        do {
            timeline.stamp(.modelRequested)
            var reply = try await generator.generateReply(request)
            reply.linksReadCount = links.count
            timeline.stamp(.modelAnswered, note: reply.expectsMore ? "모델이 뒷말을 예상했습니다." : nil)
            return Attempt(outcome: .success(reply), timeline: timeline)
        } catch {
            timeline.stamp(.failed, note: error.localizedDescription)
            return Attempt(outcome: .failure(error), timeline: timeline)
        }
    }

    /// 채팅방 요약 as it stands, or nil for a room that has never had one.
    ///
    /// One local read and no writing. Whether the note is due for a refresh is not
    /// asked here: a reply that waited on a second model call would arrive minutes
    /// late for the sake of context it will have next time anyway. A room with no
    /// note builds the same prompt it built before this existed.
    private func summary(
        for room: ChatRoom,
        account: AccountProfile,
        policy: RoomPolicy
    ) async -> String? {
        guard policy.remembersConversation, let summaryStore else { return nil }
        let stored = try? await summaryStore.summary(for: room, accountFingerprint: account.fingerprint)
        guard let stored, stored.isUsable else { return nil }
        return stored.text
    }

    /// Photos only for rooms that asked, and only the newest few.
    ///
    /// Extraction failing is not a reason to lose the answer: an empty set makes
    /// the call text-only, which is what every room did before this existed.
    private func photos(
        for messages: [ChatMessage],
        room: ChatRoom,
        policy: RoomPolicy
    ) async -> MessagePhotoSet {
        guard policy.readsPhotos, let photoSource else { return .none }
        let candidates = MessagePhotoSelection.candidates(in: messages)
        guard !candidates.isEmpty else { return .none }
        return await photoSource.photos(for: candidates, in: room)
    }

    /// Pages only for rooms that asked, and only the newest few links.
    ///
    /// Like photos, a reader that comes back empty — nothing pasted, or nothing
    /// that would open — just makes the call text-only, which is every room's
    /// behaviour before this existed.
    private func links(
        for messages: [ChatMessage],
        room: ChatRoom,
        policy: RoomPolicy
    ) async -> [MessageLink] {
        guard policy.readsLinks, let linkSource else { return [] }
        return await linkSource.links(for: messages, in: room)
    }

    /// One line naming the extra material riding along, or nil when it is only
    /// the conversation. Kept in one place so the photo count and the link count
    /// read the same way rather than each inventing a phrasing.
    private static func contextNote(photoCount: Int, linkCount: Int) -> String? {
        var parts: [String] = []
        if photoCount > 0 { parts.append("사진 \(photoCount)장") }
        if linkCount > 0 { parts.append("링크 \(linkCount)개") }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: ", ") + "을(를) 함께 보냅니다."
    }
}
