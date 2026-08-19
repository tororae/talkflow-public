import Foundation
import TalkFlowDomain

/// 사람 기억, written by the call that was already being made.
///
/// This is the entire reason the feature costs nothing. The 채팅방 요약 refresh
/// runs about seven times a day on one measured account against roughly two
/// thousand reply judgements, it already reads the room's recent conversation,
/// and it already holds the previous text so it can work incrementally. Asking a
/// second time for the same material would have doubled the only part of this
/// app that spends money with nobody having spoken.
extension ConversationSummaryRefresher {
    /// Who this room is allowed to write about, narrowed to who actually spoke in
    /// the conversation being read.
    ///
    /// Two filters, and the second one is the load-bearing one. Being answered
    /// three times says a note about this person could ever be useful — the reply
    /// it exists for has happened before. Speaking in *these* messages says there
    /// is something to learn right now. Without the second, the room hands over
    /// everybody it has ever answered: 60 people in the largest measured room
    /// against 5 who appear in the forty messages the model is given, so 55 of
    /// them arrive with no evidence attached and the only honest thing the model
    /// can do is copy their existing notes back. That is 18,000 characters of
    /// transcription demanded alongside the room summary, and it was crowding out
    /// the answer: 60 people asked for, 14 returned, 46 silently dropped with
    /// nothing recorded to say so. Every room was the same — 42→9, 27→5, 12→4.
    ///
    /// Bounding it this way needs no cap, because the conversation window already
    /// is one. Forty messages cannot carry more than forty speakers, so the list
    /// stops growing when the room does.
    ///
    /// It also retires two prompt rules that only existed to survive the mismatch
    /// — copy the note back when nothing is new, never delete on absent evidence.
    /// A person who is not asked about keeps their note untouched, so absence is
    /// handled by not asking rather than by instruction.
    ///
    /// The reply count comes from the action log, which already records the sender
    /// of every message that produced a reply. There is no roster to keep in sync
    /// and nothing new to collect.
    func eligiblePeople(
        in room: ChatRoom,
        accountFingerprint: String,
        speaking messages: [ChatMessage]
    ) async -> [PersonNote] {
        guard let personNotes, let policyStore, let actionLog,
              let policy = try? await policyStore.policy(for: room, accountFingerprint: accountFingerprint),
              policy.remembersPeople
        else {
            return []
        }
        guard let counts = try? await actionLog.replyCountsBySender(
            chatRoomID: room.id,
            accountFingerprint: accountFingerprint
        ) else {
            return []
        }
        // Own messages are excluded for the same reason they are everywhere else:
        // this account is not a person it keeps notes about.
        let spoke = Set(messages.filter { !$0.isFromMe }.map(\.sender.id))
        guard !spoke.isEmpty else { return [] }

        var eligible: [PersonNote] = []
        for (senderID, name, count) in counts
        where count >= Self.replyThreshold && spoke.contains(senderID) {
            let existing = try? await personNotes.note(inRoom: room.id, senderID: senderID)
            eligible.append(
                existing ?? PersonNote(
                    chatRoomID: room.id,
                    senderID: senderID,
                    displayName: name,
                    note: "",
                    updatedAt: Date(timeIntervalSince1970: 0)
                )
            )
        }
        return eligible
    }

    /// Stores what came back, and refuses everything it did not ask about.
    ///
    /// The model is handed a list and told to write about those people. A note
    /// keyed to somebody who is not on that list is either a hallucinated id or a
    /// conversation that talked its way into the answer, and neither is a person
    /// this room agreed to remember.
    ///
    /// A hand-edited note is left alone, the bargain 채팅방 요약 already makes:
    /// what somebody wrote about their own friend outranks what a model inferred
    /// from a few days of chat.
    func savePeople(
        _ updates: [PersonNoteUpdate],
        seenIn messages: [ChatMessage],
        known: [PersonNote],
        now: Date
    ) async {
        guard let personNotes, !known.isEmpty else { return }
        let allowed = Dictionary(known.map { ($0.senderID, $0) }, uniquingKeysWith: { first, _ in first })
        let newestName = Dictionary(
            messages.filter { !$0.isFromMe }.map { ($0.sender.id, $0.sender.displayName) },
            uniquingKeysWith: { _, latest in latest }
        )

        for update in updates {
            guard let previous = allowed[update.senderID], !previous.isPinned else { continue }
            // The room comes from the note that was read, not from an argument, so
            // an answer can only ever be written back to the room it was asked
            // about. There is no path here that moves a note between rooms.
            let note = PersonNote(
                chatRoomID: previous.chatRoomID,
                senderID: update.senderID,
                displayName: newestName[update.senderID] ?? previous.displayName,
                note: update.note,
                links: Self.merging(update.links, with: previous.links, at: now),
                // Unpinned by definition — the guard above skipped every pinned
                // note — but written from the note that was read rather than as a
                // literal, so this cannot be the line that loses somebody's pin.
                isPinned: previous.isPinned,
                coveredThroughMessageID: messages.last?.id ?? previous.coveredThroughMessageID,
                updatedAt: now
            )
            // Empty means there is nothing worth keeping about this person in this
            // room, and it is honoured — including against a note that already
            // exists. Not recording is a legitimate answer, and the prompt now
            // asks for it: a note whose every item has finished should end up
            // empty rather than carrying last week's errand forever.
            //
            // Safe because this loop only sees people the model was handed and
            // skips anything hand-edited, so an empty answer is a decision about a
            // named person and never a hand-written note being lost.
            guard !note.isEmpty else {
                try? await personNotes.delete(
                    inRoom: previous.chatRoomID,
                    senderID: update.senderID
                )
                continue
            }
            try? await personNotes.save(note)
        }
    }

    /// Keeps a link's history when this refresh did not see it come up.
    ///
    /// The model is asked whether a link was mentioned in the conversation it was
    /// handed, which is the only thing it can know. When it says no, that is not
    /// "never mentioned" — it is "not in these forty messages" — so the instant
    /// already on record stands. Overwriting it with nil would push every link a
    /// room has stopped talking about to the bottom on the first quiet refresh.
    static func merging(
        _ fresh: [PersonLink],
        with previous: [PersonLink],
        at now: Date
    ) -> [PersonLink] {
        let seen = Dictionary(previous.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
        return fresh.map { link in
            guard link.lastMentionedAt == nil else { return link }
            var kept = link
            kept.lastMentionedAt = seen[link.url]?.lastMentionedAt
            return kept
        }
    }

    static var replyThreshold: Int { PersonNote.replyThreshold }
}
