import Foundation

public struct ReplyDraft: Equatable, Sendable {
    public enum Confidence: String, Equatable, Sendable {
        case low
        case medium
        case high

        public var title: String {
            switch self {
            case .low: "낮음"
            case .medium: "보통"
            case .high: "높음"
            }
        }
    }

    public let shouldReply: Bool
    public let mode: ReplyTrigger
    public let confidence: Confidence
    public let text: String?
    /// Why the model passed, in its own words. Nil when it replied, and nil on
    /// anything a model returned before this field existed.
    public let declineReason: String?
    /// The model's own reading of whether the person is still mid-thought.
    ///
    /// This is the only thing that makes a reply wait. It used to be a list of
    /// Korean connectives and a five-second burst window — the app guessing at
    /// something it was reading the conversation anyway to answer — and then a
    /// second guess at the far end of the pipeline, where any further message
    /// cancelled the finished draft outright.
    ///
    /// Defaults to false, which is also what a provider that has never heard of
    /// the field produces: no wait, send it.
    public let expectsMore: Bool
    /// How many web searches the model ran while producing this — 0 when it did
    /// not, and for every provider that cannot search. Metadata about the call
    /// rather than part of the answer, so it is set after the reply comes back
    /// rather than carried in the schema, and it rides along only to be shown,
    /// never to change what is sent.
    public var webSearchCount: Int
    /// How many links the app opened and fed to this call — 0 when the room does
    /// not read links or nothing could be opened. Metadata like `webSearchCount`,
    /// set after the call, shown but never acted on.
    public var linksReadCount: Int
    /// Set by the deciding call when the model wants a web lookup before it can
    /// answer, so it can say so in its own words first. `searchTopic` names what
    /// to look up; `ackMessage` is the model's own "잠깐 알아볼게요", written in its
    /// voice rather than from a fixed template. All nil/false on a direct answer
    /// and on providers that never defer.
    public let needsWebSearch: Bool
    public let searchTopic: String?
    public let ackMessage: String?

    public init(
        shouldReply: Bool,
        mode: ReplyTrigger,
        confidence: Confidence,
        text: String?,
        declineReason: String? = nil,
        expectsMore: Bool = false,
        webSearchCount: Int = 0,
        linksReadCount: Int = 0,
        needsWebSearch: Bool = false,
        searchTopic: String? = nil,
        ackMessage: String? = nil
    ) {
        self.shouldReply = shouldReply
        self.mode = mode
        self.confidence = confidence
        self.text = text
        self.declineReason = declineReason
        self.expectsMore = expectsMore
        self.webSearchCount = webSearchCount
        self.linksReadCount = linksReadCount
        self.needsWebSearch = needsWebSearch
        self.searchTopic = searchTopic
        self.ackMessage = ackMessage
    }

    /// Whether this answer is worth waiting on rather than acting on.
    ///
    /// A pass counts, and has to. Asked about a sentence that stops mid-thought
    /// the model does not usually write half an answer and flag it — it declines
    /// and flags, which reads as "not yet, they are still talking". Treating that
    /// as nothing to wait for would record a 보류 against the half-sentence, and
    /// the rest of the thought would then need a whole detection cycle and a
    /// second call to be answered at all.
    public var wantsFollowUp: Bool {
        expectsMore
    }

    /// A reply the app is willing to act on: the model said yes and gave text.
    public var usableText: String? {
        guard shouldReply, let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The reason as a record may carry it, or nil to keep the old sentence.
    ///
    /// Keyed on `usableText` rather than on `shouldReply` so a record cannot
    /// contradict itself: the same value decides whether the row is a 보류, and a
    /// model that says yes, returns no text and explains itself anyway still
    /// produces a hold that says why.
    ///
    /// Nil for a blank reason as well as a missing one. Older rows have none and
    /// never will, a model can return the field empty, and both have to keep
    /// reading as they read today rather than turning into an empty cell.
    public var usableDeclineReason: String? {
        guard usableText == nil, let declineReason else { return nil }
        let cleaned = Self.singleLine(ConversationFence.neutralised(declineReason))
        guard !cleaned.isEmpty else { return nil }
        return Self.bounded(cleaned)
    }

    /// One table cell and one line of a detail pane. Longer than the 40 자 the
    /// prompt asks for, because trimming a well-behaved answer that ran four
    /// characters over buys nothing; this is the guard against a model that
    /// ignored the instruction, not a second statement of it.
    public static let declineReasonLimit = 60

    private static func bounded(_ reason: String) -> String {
        guard reason.count > declineReasonLimit else { return reason }
        // Says it was cut. A silently shortened sentence reads as a whole one,
        // and a reason that ends mid-word is a reason the reader mistrusts.
        return String(reason.prefix(declineReasonLimit - 1)) + "…"
    }

    /// Folded to one line before it is stored, not while it is drawn. The record
    /// is read in a single-line table cell and in a one-line row of the detail
    /// pane, and neither place is where a stray newline should be discovered.
    private static func singleLine(_ text: String) -> String {
        text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

/// What the model is being asked for on this call.
///
/// Three prompts, one round trip and one response shape. The schema already asks
/// for a decision and a reason, and "지금 꺼낼 말이 없다" is the same answer as
/// "답할 필요가 없다" as far as the record is concerned.
///
/// No longer raw-valued, since one of the three carries which transition it is
/// announcing. Nothing read the raw value: the intent picks a prompt and is never
/// stored, because what ends up in a record is the row's own kind.
public enum ReplyIntent: Equatable, Sendable {
    case reply
    /// Nothing was asked. The model is being handed a room that has gone quiet
    /// and asked whether there is anything worth opening.
    case openConversation
    /// Nothing was asked here either, and nothing in the room prompted it. The
    /// account's own availability moved — a burn started or ended, the answering
    /// window opened or is about to close — and the model is asked whether this
    /// room should hear about it. Usually it should not.
    case announce(StateAnnouncement)
}

/// How web search figures into one reply call.
///
/// The tool is a server-side one, so whether it is on is orthogonal to the
/// read-only sandbox; what varies is when the model may reach for it and how the
/// prompt frames it.
public enum SearchStage: Sendable, Equatable {
    /// No web search. The model answers from the conversation alone.
    case none
    /// Search inline within this one call — a room that reads the web but leaves
    /// replies as drafts, so there is nobody to acknowledge to first.
    case inline
    /// The deciding call for a room that acknowledges first: the tool is off, and
    /// the model may defer by setting `needs_web_search` with a topic and its own
    /// "잠깐 알아볼게요" rather than answering now.
    case mayDefer
    /// The answering call after an acknowledgement went out: the tool is on, and
    /// the model continues naturally from what it already said.
    case answering(ackedWith: String)

    /// Whether the server-side web_search tool is offered on this call.
    public var toolEnabled: Bool {
        switch self {
        case .none, .mayDefer: false
        case .inline, .answering: true
        }
    }
}

public struct ReplyDraftRequest: Sendable {
    public let room: ChatRoom
    /// Defaulted rather than required, unlike `answeringCondition`. Only one
    /// place builds an opener, and the value it would fall back to is the
    /// behaviour every other caller already has — a forgotten flag here writes a
    /// reply, not an unasked-for message.
    public let intent: ReplyIntent
    public let trigger: ReplyTrigger
    public let triggerMessageID: String
    /// Chronological, oldest first.
    public let recentMessages: [ChatMessage]
    /// Already resolved: the room's own style when it has one, otherwise the
    /// global. The builder is handed the answer rather than the two candidates,
    /// so no prompt can be written from a style nobody chose.
    public let style: ResponseStyle
    /// 답변 조건, likewise already resolved. No default: a condition that quietly
    /// failed to reach the prompt would be one more setting in this app that
    /// promises a difference it does not make, so leaving it out is a compile
    /// error.
    public let answeringCondition: AnsweringCondition
    public let conversationSummary: String?
    /// What is known about the person whose message is being judged, and only
    /// that person.
    ///
    /// Not everybody in the room. A note is a written file about somebody, and
    /// attaching eight of them to answer one message would send seven people's
    /// files to the provider for no reason and push the conversation itself out
    /// of the prompt. The one who just spoke is the one the answer is for.
    public let senderNote: PersonNote?
    /// Carried on the request rather than read from anywhere global, because it
    /// is the room's setting and the prompt is built one room at a time.
    /// Photos from `recentMessages` that the provider may attach, in the order
    /// the prompt numbers them. Empty unless the room turned photos on, and
    /// empty again whenever extraction came back with nothing.
    public let photos: [MessagePhoto]
    /// Pages opened from links in `recentMessages`, their text already rendered
    /// and bounded. Empty unless the room turned link reading on, and empty again
    /// when nothing could be opened. Untrusted like the messages themselves — see
    /// the prompt's link section.
    public let links: [MessageLink]
    /// How many older messages were dropped to keep this call bounded.
    ///
    /// Told to the model rather than hidden, because a thread that starts
    /// mid-argument reads as a complete thread that makes no sense, and the model
    /// answers it as if it had the beginning.
    public let omittedMessageCount: Int
    /// How web search figures into this call — off, inline, the deciding call
    /// that may defer, or the answering call after an acknowledgement. Carried on
    /// the request because the prompt and the tool are built one room at a time.
    public let searchStage: SearchStage
    /// A standing note the room's owner left for the opener — 「요즘 하는 프로젝트
    /// 얘기 꺼내」. Filled only on the opener path and only where the room has one;
    /// every reply and every hintless room leaves it nil, and the prompt drops the
    /// line entirely rather than send a blank instruction. Guidance rather than a
    /// script: the prompt is told to reach for it only when the conversation gives
    /// it a natural opening, because an opener that recites a memo word for word is
    /// the bot reading a memo aloud.
    public let openerHint: String?
    /// Whether this opener is a *repeat* — TalkFlow spoke last and nobody has
    /// answered since, so it is opening for the second or third time in a row (see
    /// `RoomPolicy.openerRepeatLimit`). False for a first opener and for every
    /// reply. It only decides whether the retry wording is written at all; a first
    /// opener always comes out of the room's own recent talk and needs none of it.
    public let isRepeatOpener: Bool
    /// What a repeat opener should talk about, read only when `isRepeatOpener` is
    /// true. `.carryOn` — and nil, the value every non-opener request carries —
    /// leaves the prompt to continue the thread it can already see; `.fresh` tells
    /// it to set the last opener's subject aside and try a different way in.
    public let openerRepeatTopic: OpenerRepeatTopic?

    public init(
        room: ChatRoom,
        intent: ReplyIntent = .reply,
        trigger: ReplyTrigger,
        triggerMessageID: String,
        recentMessages: [ChatMessage],
        style: ResponseStyle,
        answeringCondition: AnsweringCondition,
        conversationSummary: String? = nil,
        senderNote: PersonNote? = nil,
        photos: [MessagePhoto] = [],
        links: [MessageLink] = [],
        omittedMessageCount: Int = 0,
        searchStage: SearchStage = .none,
        openerHint: String? = nil,
        isRepeatOpener: Bool = false,
        openerRepeatTopic: OpenerRepeatTopic? = nil
    ) {
        self.room = room
        self.intent = intent
        self.trigger = trigger
        self.triggerMessageID = triggerMessageID
        self.recentMessages = recentMessages
        self.style = style
        self.answeringCondition = answeringCondition
        self.conversationSummary = conversationSummary
        self.senderNote = senderNote
        self.photos = photos
        self.links = links
        self.omittedMessageCount = omittedMessageCount
        self.searchStage = searchStage
        self.openerHint = openerHint
        self.isRepeatOpener = isRepeatOpener
        self.openerRepeatTopic = openerRepeatTopic
    }
}

/// Asks a provider whether to reply and what to say, in a single call.
///
/// Deliberately one round trip: the deterministic rules already ran, so the
/// model is only consulted about genuine candidates. A room that reads the web
/// and delivers on its own runs this twice — once to decide, which may come back
/// asking for a search (`ReplyDraft.needsWebSearch`), then once more to answer —
/// but each is the same one call, deciding reply-and-search together.
public protocol ReplyGenerator: Sendable {
    func generateReply(_ request: ReplyDraftRequest) async throws -> ReplyDraft
}
