import Foundation
import GRDB
import TalkFlowDomain

/// Turns a row of katok's archive into the model the rest of the app reads.
///
/// Kept apart from the queries because it is the other half of the schema
/// coupling: which columns exist and what their values mean, rather than which
/// rows to ask for. A row that cannot be read is no row — an archive written by
/// a katok that has moved on should cost detail, not the whole conversation.
extension ChatRoom {
    init?(archiveRow row: Row) {
        guard let id = row["chat_id"] as String?,
              let name = row["chat_name"] as String?,
              let rawKind = row["chat_type"] as String?,
              let kind = Kind(rawValue: rawKind)
        else {
            return nil
        }
        self.init(id: id, displayName: name, kind: kind)
    }
}

extension ChatMessage {
    init?(archiveRow row: Row, accountSenderID: String?, parser: ISO8601DateFormatter) {
        guard let id = row["message_id"] as String?,
              let chatRoomID = row["chat_id"] as String?,
              let senderID = row["sender_id"] as String?,
              let timestamp = row["timestamp"] as String?,
              let sentAt = parser.date(from: timestamp)
        else {
            return nil
        }

        self.init(
            id: id,
            chatRoomID: chatRoomID,
            sender: ChatMember(
                id: senderID,
                displayName: row["sender_nickname"] as String? ?? ""
            ),
            body: row["text"] as String? ?? "",
            sentAt: sentAt,
            kind: Self.kind(ofArchiveType: row["message_type"] as String? ?? ""),
            isFromMe: senderID == accountSenderID,
            // An empty id is not a reply: it names no message, yet anything that
            // only checks for nil would read it as one.
            replyToMessageID: (row["reply_to_message_id"] as String?)
                .flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    /// KakaoTalk's type vocabulary, narrowed to what TalkFlow can act on.
    ///
    /// `type_2` is a photo, and its `text` column holds the word 사진 — which is
    /// all a picture amounts to for a model unless the file itself is fetched.
    /// The remaining types are worth telling apart only in that they are not
    /// photos: `type_0` is a system feed row whose text is JSON, and asking
    /// KakaoTalk for the picture behind one of those returns nothing.
    private static func kind(ofArchiveType type: String) -> Kind {
        switch type {
        case "text": .text
        case "type_2": .photo
        default: .attachment
        }
    }
}
