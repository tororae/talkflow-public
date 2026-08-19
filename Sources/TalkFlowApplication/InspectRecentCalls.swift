import Foundation
import TalkFlowDomain

/// What a room's recent conversation did with the words that room answers to.
public struct RecentCallReport: Equatable, Sendable {
    public struct Call: Equatable, Sendable {
        /// The word that made it a call, so the screen can say which one works.
        public let sign: String
        public let senderName: String
        public let at: Date

        public init(sign: String, senderName: String, at: Date) {
            self.sign = sign
            self.senderName = senderName
            self.at = at
        }
    }

    public let examinedMessages: Int
    public let matchedMessages: Int
    public let latest: Call?
    /// The name this account goes by *in this room*, when it has one of its own.
    ///
    /// Nil means the room falls back to the account-wide name. Read here because
    /// this is already the one call the room screen makes when it opens, and the
    /// screen has to be able to say which name it is showing — a room answering
    /// to a name nobody there uses is the failure this exists to make visible.
    public let roomNickname: String?

    public init(
        examinedMessages: Int,
        matchedMessages: Int,
        latest: Call? = nil,
        roomNickname: String? = nil
    ) {
        self.examinedMessages = examinedMessages
        self.matchedMessages = matchedMessages
        self.latest = latest
        self.roomNickname = roomNickname
    }

    public static let none = RecentCallReport(examinedMessages: 0, matchedMessages: 0)
}

/// Answers "does anybody actually call this room by these words?".
///
/// A `멘션에만 응답` room that nobody addresses holds every message for
/// `notAddressed`, and that hold is deliberately kept out of the timeline: it
/// would fire on every message in every quiet room and bury the drafts and
/// failures a person has to look at. The cost is that a room set up wrong and a
/// room simply not called look identical from outside — which is exactly how a
/// working feature can look broken for a day. So the room's own screen asks the
/// question on demand instead, where the setting is.
public struct InspectRecentCalls: Sendable {
    /// The same window the reply pipeline reads, so the answer describes the
    /// messages that were actually judged rather than a different slice.
    public static let messageLimit = DraftRepliesForChangedRooms.contextMessageLimit

    private let connection: any KakaoConnection

    public init(connection: any KakaoConnection) {
        self.connection = connection
    }

    /// The same report, after throwing away whatever name was being remembered.
    ///
    /// Behind 이름 다시 읽기. The cache expires on its own, but somebody who has
    /// just renamed themselves in KakaoTalk is standing in front of the screen now,
    /// and telling them to wait a minute for a name they can see in another window
    /// is not an answer.
    public func rereadingNickname(room: ChatRoom, signs: CallSigns) async -> RecentCallReport {
        await connection.forgetAccountNickname()
        return await callAsFunction(room: room, signs: signs)
    }

    public func callAsFunction(room: ChatRoom, signs: CallSigns) async -> RecentCallReport {
        let roomNickname = await connection.accountNickname(in: room)
        guard let messages = try? await connection.recentMessages(in: room, limit: Self.messageLimit) else {
            return .none
        }

        // The room's own name takes part in the count as well as the label. A
        // report built from the account-wide name would say nobody calls this
        // room, in the one room where the name is the reason.
        let signs = roomNickname.map {
            CallSigns(nickname: $0, globalKeywords: signs.globalKeywords, roomKeywords: signs.roomKeywords)
        } ?? signs

        // Own messages are skipped: writing your own name is not being called,
        // and the engine never treats the account's own message as a trigger.
        let calls = messages.compactMap { message -> RecentCallReport.Call? in
            guard !message.isFromMe, message.kind == .text,
                  let sign = signs.matched(in: message.body)
            else {
                return nil
            }
            return RecentCallReport.Call(
                sign: sign,
                senderName: message.sender.displayName,
                at: message.sentAt
            )
        }

        return RecentCallReport(
            examinedMessages: messages.count,
            matchedMessages: calls.count,
            latest: calls.last,
            roomNickname: roomNickname
        )
    }
}
