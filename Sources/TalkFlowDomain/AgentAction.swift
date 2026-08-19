import Foundation

/// One thing TalkFlow decided or did, in the order it happened.
///
/// This is the record the user reviews to understand the bot, so a hold is kept
/// with the same weight as a reply: knowing why nothing was sent matters as much
/// as seeing what was.
public struct AgentAction: Identifiable, Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case held
        case drafted
        /// TalkFlow's own initiative: a room that had gone quiet, and a subject
        /// picked out of its own conversation with nobody having asked.
        ///
        /// Its own kind rather than a 초안 with a flag, because the timeline is
        /// where the user finds out what the app did in their name and "이건 답장이
        /// 아니라 내가 먼저 건 말" is the first thing they have to be able to see.
        /// Both outcomes wear it: an opener the model passed on carries no text,
        /// and belongs beside the ones it wrote rather than in the 보류 pile with
        /// every reply that was declined.
        case opened
        case sent
        case failed
        case dismissed
        /// A slash-command run in a designated admin room, and the reply TalkFlow
        /// sent back into it.
        ///
        /// Its own kind rather than a 전송 for the same reason `opened` is not a
        /// 초안: the timeline is where the user sees what the app did in their
        /// name, and a console reply is neither an answer to a conversation nor a
        /// message they will read as one. Keeping it apart also keeps it out of
        /// every reply-, opener- and person-pacing query, which count the other
        /// kinds and would otherwise read a command as a conversation.
        case commanded

        public var title: String {
            switch self {
            case .held: "보류"
            case .drafted: "초안 생성"
            case .opened: "먼저 말 걸기"
            case .sent: "전송"
            case .failed: "실패"
            case .dismissed: "무시함"
            case .commanded: "관리자 명령"
            }
        }
    }

    public var id: Int64
    public let accountFingerprint: String
    public let chatRoomID: String
    public let chatRoomName: String
    public let kind: Kind
    public let triggerMessageID: String?
    public let triggerSenderID: String?
    /// What the reply answers, copied at judgement time.
    public let triggerText: String?
    public let triggerSenderName: String?
    /// The run of conversation this answers, copied at judgement time.
    ///
    /// Usually longer than the one trigger above, which is the reason it exists:
    /// 뒷말 대기 and 판단 주기 both make one reply answer several messages. Nil on
    /// rows written before runs were recorded and on rows that answered nothing,
    /// so the trigger fields stay — the screen still reads those rows off them,
    /// and the send queue keys on the trigger message either way.
    public let answeredRun: AnsweredRun?
    public let replyMode: ReplyTrigger?
    public let confidence: ReplyDraft.Confidence?
    public let replyText: String?
    public let detail: String
    public let contextMessageCount: Int
    /// Where the time went on the way to this row.
    ///
    /// Empty on rows written before this existed and on rows nothing waited for
    /// — a dismissal is instant and has no story to tell. The screen leaves the
    /// section out entirely in that case rather than showing an empty box.
    public let timeline: ActionTimeline
    public let createdAt: Date

    public init(
        id: Int64 = 0,
        accountFingerprint: String,
        chatRoomID: String,
        chatRoomName: String = "",
        kind: Kind,
        triggerMessageID: String? = nil,
        triggerSenderID: String? = nil,
        triggerText: String? = nil,
        triggerSenderName: String? = nil,
        answeredRun: AnsweredRun? = nil,
        replyMode: ReplyTrigger? = nil,
        confidence: ReplyDraft.Confidence? = nil,
        replyText: String? = nil,
        detail: String,
        contextMessageCount: Int = 0,
        timeline: ActionTimeline = ActionTimeline(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.accountFingerprint = accountFingerprint
        self.chatRoomID = chatRoomID
        self.chatRoomName = chatRoomName
        self.kind = kind
        self.triggerMessageID = triggerMessageID
        self.triggerSenderID = triggerSenderID
        self.triggerText = triggerText
        self.triggerSenderName = triggerSenderName
        self.answeredRun = answeredRun
        self.replyMode = replyMode
        self.confidence = confidence
        self.replyText = replyText
        self.detail = detail
        self.contextMessageCount = contextMessageCount
        self.timeline = timeline
        self.createdAt = createdAt
    }
}

public protocol AgentActionLog: Sendable {
    func record(_ action: AgentAction) async throws
    func recent(limit: Int) async throws -> [AgentAction]
    func recent(chatRoomID: String, limit: Int) async throws -> [AgentAction]
    /// When TalkFlow last replied in a room, which the cooldown rule needs.
    func lastReplyDate(chatRoomID: String, accountFingerprint: String) async throws -> Date?

    /// When the model was last asked about a room, which paces a room that
    /// judges in batches.
    ///
    /// Distinct from `lastReplyDate` because the interval bounds spending, and
    /// most calls in the rooms this setting exists for come back with nothing to
    /// send. Anchoring on replies would leave such a room paying per message
    /// while looking, from the outside, like it never answers.
    func lastJudgementDate(chatRoomID: String, accountFingerprint: String) async throws -> Date?

    /// Whether a message has already been judged. A sync fires whenever any room
    /// changes, so without this the same message would be sent to the model
    /// again on every unrelated update.
    func hasAction(chatRoomID: String, triggerMessageID: String) async throws -> Bool

    /// How many conversations TalkFlow has opened in this room since a moment —
    /// `opened` rows only, replies and holds excluded.
    ///
    /// The moment the caller hands in is the other side's last message, so what
    /// comes back is the length of the current run of unanswered openers — exactly
    /// what `RoomPolicy.openerRepeatLimit` bounds. A single message from anyone else
    /// moves that moment forward, so the earlier openers fall out of the window and
    /// the run reads as reset without a row being deleted.
    func openerCount(chatRoomID: String, accountFingerprint: String, since: Date) async throws -> Int

    /// How many times each person's message produced a reply in this room, with
    /// the name last recorded for them.
    ///
    /// The eligibility list for 사람 기억, and it needs no new collection: every
    /// drafted row already carries the sender that triggered it. Keyed on the id
    /// rather than the name, because two of this account's most frequent
    /// correspondents are both called 왕만두.
    func replyCountsBySender(
        chatRoomID: String,
        accountFingerprint: String
    ) async throws -> [(senderID: String, displayName: String, count: Int)]

    /// Drafts still waiting on a person: written, not delivered, not dismissed.
    ///
    /// Draft-only is the default delivery mode, so without somewhere to act on
    /// these the whole drafting stage produces nothing the user can use.
    func pendingDrafts(limit: Int) async throws -> [AgentAction]

    /// Marks a draft as handled without sending it.
    func dismissDraft(id: Int64) async throws
}
