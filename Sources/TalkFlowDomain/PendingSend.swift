import Foundation

/// A draft waiting for its conditions to be met.
///
/// Sending cannot be undone, so drafts sit in a queue that is re-checked rather
/// than being delivered the moment they are generated.
public struct PendingSend: Identifiable, Equatable, Sendable {
    public enum State: String, Equatable, Sendable {
        case waiting
        case sent
        case cancelled
        case failed

        public var title: String {
            switch self {
            case .waiting: "대기"
            case .sent: "전송됨"
            case .cancelled: "취소"
            case .failed: "실패"
            }
        }
    }

    public var id: Int64
    public let accountFingerprint: String
    public let chatRoomID: String
    public let chatRoomName: String
    public let triggerMessageID: String
    /// Who said the thing this reply answers.
    ///
    /// The staleness check needs it: a reply goes stale when the person being
    /// answered says more, not when anybody in the room speaks. Without the
    /// sender there is no way to tell those apart.
    public let triggerSenderID: String?
    /// For an opener, the newest message in the room when it was written. Nil for
    /// a reply.
    ///
    /// An opener was composed for a room that had gone quiet, so anybody speaking
    /// between writing it and sending it takes away the only reason it was
    /// allowed. It is the id rather than a flag because the check is "did this
    /// room say anything", and the id is what answers that at delivery time.
    public let opensConversationAfterMessageID: String?
    public let text: String
    /// The end of the settling delay; nothing is sent before this.
    public let eligibleAt: Date
    public var state: State
    public var detail: String
    public let createdAt: Date

    public init(
        id: Int64 = 0,
        accountFingerprint: String,
        chatRoomID: String,
        chatRoomName: String = "",
        triggerMessageID: String,
        triggerSenderID: String? = nil,
        opensConversationAfterMessageID: String? = nil,
        text: String,
        eligibleAt: Date,
        state: State = .waiting,
        detail: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.accountFingerprint = accountFingerprint
        self.chatRoomID = chatRoomID
        self.chatRoomName = chatRoomName
        self.triggerMessageID = triggerMessageID
        self.triggerSenderID = triggerSenderID
        self.opensConversationAfterMessageID = opensConversationAfterMessageID
        self.text = text
        self.eligibleAt = eligibleAt
        self.state = state
        self.detail = detail
        self.createdAt = createdAt
    }
}

public protocol PendingSendStore: Sendable {
    func enqueue(_ send: PendingSend) async throws
    func waiting() async throws -> [PendingSend]
    func recent(limit: Int) async throws -> [PendingSend]
    func resolve(id: Int64, state: PendingSend.State, detail: String) async throws
}

/// Who asked for a send, which decides which of the safety rules still apply.
///
/// The rules that protect a person from the app are not the rules that protect
/// them from themselves, and only one of the two makes sense when they pressed
/// the button.
public enum SendOrigin: Equatable, Sendable {
    /// The queue decided the conditions were met. Nobody asked for this now, and
    /// nobody is expecting KakaoTalk to move.
    case automatic
    /// A person pressed 보내기 and is watching for it to happen.
    case userRequested
}

/// How a delivered message actually got there.
///
/// There are two ways in and they cost about ten times apart — typing into a
/// window that is already open takes about a second, and driving KakaoTalk's
/// interface to open a closed one takes ten to twenty. Which one ran was not
/// recorded, so a send that took twenty-three seconds looked exactly like one
/// that took one, and the difference is the whole question.
public struct SendReceipt: Equatable, Sendable {
    public enum Route: String, Equatable, Sendable {
        /// Typed straight into an open window. Takes no focus.
        case direct
        /// Drove KakaoTalk's interface, which can mean opening the room first.
        case katok

        public var title: String {
            switch self {
            case .direct: "직접 입력"
            case .katok: "katok"
            }
        }
    }

    public let route: Route
    /// How many tries it took. More than one means the earlier ones failed in a
    /// way worth retrying, and each carried the cost of the route again.
    public let attempts: Int
    /// Why the direct route was not the one used. Nil when it was.
    public let fellBackBecause: String?

    public init(route: Route, attempts: Int = 1, fellBackBecause: String? = nil) {
        self.route = route
        self.attempts = attempts
        self.fellBackBecause = fellBackBecause
    }

    /// One line for the timeline, saying which way it went and what that cost.
    public var explanation: String {
        var text = "\(route.title)(으)로 보냈습니다."
        if attempts > 1 { text += " \(attempts)번째 시도." }
        if let fellBackBecause { text += " 직접 입력 불가: \(fellBackBecause)" }
        return text
    }
}

/// Delivers a message to a chat room. The only write path in the app.
///
/// The id is what decides which room, always — names are not unique and a
/// name-based send can land in the wrong conversation. The name comes along
/// because KakaoTalk's own windows are titled by it, and a sender that types
/// into one has nothing else to find it by.
public protocol MessageSender: Sendable {
    @discardableResult
    func send(
        text: String,
        toChatRoomID chatRoomID: String,
        named chatRoomName: String,
        origin: SendOrigin
    ) async throws -> SendReceipt
}
