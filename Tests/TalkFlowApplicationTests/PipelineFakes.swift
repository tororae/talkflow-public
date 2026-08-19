import Foundation
import TalkFlowDomain

let testAccount = AccountProfile(label: "테스트", fingerprint: "katok-test")
let testDirectRoom = ChatRoom(id: "room-d", displayName: "가족", kind: .direct)
let testGroupRoom = ChatRoom(id: "room-g", displayName: "프로젝트 팀", kind: .group)

/// The default instant is shared by every message, which suits the tests that
/// only care about order. A test about what accumulated since the last
/// judgement has to place its messages on the clock, so it says when.
func testMessage(
    id: String,
    roomID: String = testDirectRoom.id,
    senderID: String = "s1",
    body: String,
    kind: ChatMessage.Kind = .text,
    isFromMe: Bool = false,
    sentAt: Date = Date(timeIntervalSince1970: 1_000_000)
) -> ChatMessage {
    ChatMessage(
        id: id,
        chatRoomID: roomID,
        sender: ChatMember(id: senderID, displayName: "지수"),
        body: body,
        sentAt: sentAt,
        kind: kind,
        isFromMe: isFromMe
    )
}

/// Stands in for the katok extractor, and remembers both what it was asked for
/// and whether the files were cleaned up afterwards.
///
/// A locked class rather than an actor because `discard` is synchronous by
/// design: the pipeline calls it from `defer`, where nothing can be awaited.
final class FakePhotoSource: MessagePhotoSource, @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [[String]] = []
    private var discards = 0
    private let extracted: [MessagePhoto]

    init(extracted: [MessagePhoto] = []) {
        self.extracted = extracted
    }

    func photos(for messages: [ChatMessage], in room: ChatRoom) async -> MessagePhotoSet {
        lock.withLock { requests.append(messages.map(\.id)) }

        guard !extracted.isEmpty else { return .none }
        return MessagePhotoSet(
            directoryURL: URL(fileURLWithPath: "/tmp/talkflow-photos-test"),
            photos: extracted
        )
    }

    func discard(_ set: MessagePhotoSet) {
        lock.withLock { discards += 1 }
    }

    var requestedMessageIDs: [[String]] {
        lock.withLock { requests }
    }

    var discardCount: Int {
        lock.withLock { discards }
    }
}

func testPhoto(messageID: String) -> MessagePhoto {
    MessagePhoto(
        messageID: messageID,
        fileURL: URL(fileURLWithPath: "/tmp/talkflow-photos-test/\(messageID).jpg")
    )
}

actor FakeKakaoConnection: KakaoConnection {
    private let statusValue: KakaoConnectionStatus
    private let rooms: [ChatRoom]
    private let messagesByRoom: [String: [ChatMessage]]
    /// katok rewrites the archive every few seconds, so a read can simply fail.
    private let roomsFailure: Error?

    init(
        status: KakaoConnectionStatus = .connected(account: testAccount),
        rooms: [ChatRoom] = [testDirectRoom],
        messagesByRoom: [String: [ChatMessage]] = [:],
        roomsFailure: Error? = nil
    ) {
        statusValue = status
        self.rooms = rooms
        self.messagesByRoom = messagesByRoom
        self.roomsFailure = roomsFailure
    }

    func status() async -> KakaoConnectionStatus { statusValue }

    func chatRooms() async throws -> [ChatRoom] {
        if let roomsFailure { throw roomsFailure }
        return rooms
    }

    func recentMessages(in chatRoom: ChatRoom, limit: Int) async throws -> [ChatMessage] {
        Array((messagesByRoom[chatRoom.id] ?? []).suffix(limit))
    }
}

/// A room a test can talk into while the pipeline is running.
///
/// The 뒷말 대기 reads, waits, and reads again, so a test of it needs a message to
/// arrive *between* those two reads. Injecting it from the pause is the same
/// order of events as somebody finishing their sentence while TalkFlow holds off.
actor MutableKakaoConnection: KakaoConnection {
    private let room: ChatRoom
    private var messages: [ChatMessage]
    private(set) var readCount = 0

    init(room: ChatRoom = testDirectRoom, messages: [ChatMessage] = []) {
        self.room = room
        self.messages = messages
    }

    func status() async -> KakaoConnectionStatus { .connected(account: testAccount) }
    func chatRooms() async throws -> [ChatRoom] { [room] }

    func recentMessages(in chatRoom: ChatRoom, limit: Int) async throws -> [ChatMessage] {
        readCount += 1
        return Array(messages.suffix(limit))
    }

    func receive(_ message: ChatMessage) {
        messages.append(message)
    }

    func hold(_ messages: [ChatMessage]) {
        self.messages = messages
    }
}

actor FakePolicyStore: RoomPolicyStore {
    private var stored: [String: RoomPolicy]

    init(_ policies: [RoomPolicy] = []) {
        stored = policies.reduce(into: [:]) { $0[$1.chatRoomID] = $1 }
    }

    func policy(for room: ChatRoom, accountFingerprint: String) async throws -> RoomPolicy {
        stored[room.id] ?? .makeDefault(accountFingerprint: accountFingerprint, room: room)
    }

    func policies(accountFingerprint: String) async throws -> [String: RoomPolicy] { stored }
    func save(_ policy: RoomPolicy) async throws { stored[policy.chatRoomID] = policy }
    func rememberRooms(_ rooms: [ChatRoom], accountFingerprint: String) async throws {}

    private var hiddenRooms: Set<String> = []

    func hiddenRoomIDs(accountFingerprint: String) async throws -> Set<String> { hiddenRooms }

    func setRoomHidden(_ hidden: Bool, chatRoomID: String, accountFingerprint: String) async throws {
        if hidden { hiddenRooms.insert(chatRoomID) } else { hiddenRooms.remove(chatRoomID) }
    }

    /// Derived rather than stubbed, so a test that leaves every room on the
    /// default answers the way a real store would: no.
    func anyRoomOpensConversations() async throws -> Bool {
        stored.values.contains { $0.conversationOpener.isOn }
    }
}

actor FakeSettingsStore: AppSettingsStore {
    private var enabled: Bool
    private var style: ResponseStyle
    private var condition: AnsweringCondition
    private var usePolicyAccepted: Bool

    private var wakesDisplay: Bool
    private var model: AIModelChoice

    init(
        enabled: Bool = true,
        style: ResponseStyle = ResponseStyle(responseKeywords: ["한결"]),
        condition: AnsweringCondition = .empty,
        usePolicyAccepted: Bool = true,
        wakesDisplay: Bool = true,
        model: AIModelChoice = .codexDefault
    ) {
        self.enabled = enabled
        self.style = style
        self.condition = condition
        self.usePolicyAccepted = usePolicyAccepted
        self.wakesDisplay = wakesDisplay
        self.model = model
    }

    func responseStyle() async throws -> ResponseStyle { style }
    func save(_ style: ResponseStyle) async throws { self.style = style }
    func answeringCondition() async throws -> AnsweringCondition { condition }
    func save(_ condition: AnsweringCondition) async throws { self.condition = condition }
    func globalResponsesEnabled() async throws -> Bool { enabled }
    func setGlobalResponsesEnabled(_ enabled: Bool) async throws { self.enabled = enabled }
    func launchesAtLogin() async throws -> Bool { false }
    func setLaunchesAtLogin(_ enabled: Bool) async throws {}
    func sendUsePolicyAccepted() async throws -> Bool { usePolicyAccepted }
    func setSendUsePolicyAccepted(_ accepted: Bool) async throws { usePolicyAccepted = accepted }
    func wakesDisplayToSend() async throws -> Bool { wakesDisplay }
    func setWakesDisplayToSend(_ enabled: Bool) async throws { wakesDisplay = enabled }
    func aiModel() async throws -> AIModelChoice { model }
    func setAIModel(_ choice: AIModelChoice) async throws { model = choice }
}

/// Unlocks on wake, the way macOS does inside the password grace period.
actor FakeDisplayWaker: DisplayWaker {
    private(set) var wakeCount = 0
    private let monitor: MutableActivityMonitor

    init(monitor: MutableActivityMonitor) {
        self.monitor = monitor
    }

    func wake() async {
        wakeCount += 1
        await monitor.unlock()
    }
}

/// A waker for screens that stay locked, as they do once macOS asks for a
/// password.
actor StubbornDisplayWaker: DisplayWaker {
    private(set) var wakeCount = 0
    func wake() async { wakeCount += 1 }
}

final class MutableActivityMonitor: SystemActivityMonitor, @unchecked Sendable {
    private let lock = NSLock()
    private var value: SystemActivitySnapshot

    init(idleSeconds: TimeInterval = 60, screenLocked: Bool = true) {
        value = SystemActivitySnapshot(idleSeconds: idleSeconds, screenLocked: screenLocked)
    }

    func snapshot() -> SystemActivitySnapshot {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func unlock() {
        lock.lock()
        defer { lock.unlock() }
        value = SystemActivitySnapshot(idleSeconds: value.idleSeconds, screenLocked: false)
    }
}

actor FakeSendStore: PendingSendStore {
    private(set) var queued: [PendingSend] = []
    private(set) var resolutions: [(id: Int64, state: PendingSend.State, detail: String)] = []
    private var nextID: Int64 = 1

    init(_ initial: [PendingSend] = []) {
        for send in initial { queued.append(send) }
    }

    func enqueue(_ send: PendingSend) async throws {
        var stored = send
        stored.id = nextID
        nextID += 1
        queued.append(stored)
    }

    func waiting() async throws -> [PendingSend] { queued.filter { $0.state == .waiting } }
    func recent(limit: Int) async throws -> [PendingSend] { queued }

    func resolve(id: Int64, state: PendingSend.State, detail: String) async throws {
        resolutions.append((id, state, detail))
        guard let index = queued.firstIndex(where: { $0.id == id }) else { return }
        queued[index].state = state
        queued[index].detail = detail
    }
}

actor FakeMessageSender: MessageSender {
    private(set) var sent: [(text: String, chatRoomID: String)] = []
    private let failure: Error?

    init(failure: Error? = nil) {
        self.failure = failure
    }

    func send(
        text: String,
        toChatRoomID chatRoomID: String,
        named chatRoomName: String,
        origin: SendOrigin
    ) async throws -> SendReceipt {
        if let failure { throw failure }
        sent.append((text, chatRoomID))
        return SendReceipt(route: .direct)
    }
}

struct FixedActivityMonitor: SystemActivityMonitor {
    let value: SystemActivitySnapshot

    init(idleSeconds: TimeInterval = 60, screenLocked: Bool = false) {
        value = SystemActivitySnapshot(idleSeconds: idleSeconds, screenLocked: screenLocked)
    }

    func snapshot() -> SystemActivitySnapshot { value }
}

actor FakeActionLog: AgentActionLog {
    private(set) var recorded: [AgentAction] = []
    private var lastReply: Date?
    private var lastJudgement: Date?
    private var replyCounts: [(senderID: String, displayName: String, count: Int)]

    init(
        lastReply: Date? = nil,
        lastJudgement: Date? = nil,
        existing: [AgentAction] = [],
        replyCounts: [(senderID: String, displayName: String, count: Int)] = []
    ) {
        self.lastReply = lastReply
        self.lastJudgement = lastJudgement
        recorded = existing
        self.replyCounts = replyCounts
    }

    func record(_ action: AgentAction) async throws { recorded.append(action) }
    func recent(limit: Int) async throws -> [AgentAction] { recorded }
    func recent(chatRoomID: String, limit: Int) async throws -> [AgentAction] {
        recorded.filter { $0.chatRoomID == chatRoomID }
    }

    func lastReplyDate(chatRoomID: String, accountFingerprint: String) async throws -> Date? {
        lastReply
    }

    /// Mirrors the repository's rule — a context count means a request was
    /// built — so a batch paces itself off the calls this log actually saw
    /// rather than off a number the test had to keep in step by hand.
    func lastJudgementDate(chatRoomID: String, accountFingerprint: String) async throws -> Date? {
        let judged = recorded
            .filter { $0.chatRoomID == chatRoomID && $0.contextMessageCount > 0 }
            .map(\.createdAt)
            .max()
        return judged ?? lastJudgement
    }

    func hasAction(chatRoomID: String, triggerMessageID: String) async throws -> Bool {
        recorded.contains { $0.chatRoomID == chatRoomID && $0.triggerMessageID == triggerMessageID }
    }

    /// The run of openers since a moment, counted the way the repository counts it:
    /// `opened` rows for this room after `since`. The sweep hands in the other
    /// side's last message, so this is the unanswered run the gate bounds.
    func openerCount(chatRoomID: String, accountFingerprint: String, since: Date) async throws -> Int {
        recorded.filter {
            $0.chatRoomID == chatRoomID
                && $0.accountFingerprint == accountFingerprint
                && $0.kind == .opened
                && $0.createdAt > since
        }.count
    }

    /// Openers count, the way the repository counts them: 초안만 is what they take
    /// by default, so this list is the only way most of them ever get sent.
    func pendingDrafts(limit: Int) async throws -> [AgentAction] {
        recorded.filter { ($0.kind == .drafted || $0.kind == .opened) && $0.replyText != nil }
    }

    func dismissDraft(id: Int64) async throws {
        recorded.removeAll { $0.id == id }
    }

    func replyCountsBySender(
        chatRoomID: String,
        accountFingerprint: String
    ) async throws -> [(senderID: String, displayName: String, count: Int)] { replyCounts }

}

actor FakeSummaryStore: ConversationSummaryStore {
    private var stored: [String: ConversationSummary] = [:]
    private(set) var clearedRoomIDs: [String] = []

    init(_ summaries: [ConversationSummary] = []) {
        stored = summaries.reduce(into: [:]) { $0[$1.chatRoomID] = $1 }
    }

    func summary(for room: ChatRoom, accountFingerprint: String) async throws -> ConversationSummary? {
        stored[room.id]
    }

    func summaries(accountFingerprint: String) async throws -> [String: ConversationSummary] {
        stored
    }

    func save(_ summary: ConversationSummary) async throws {
        stored[summary.chatRoomID] = summary
    }

    func clear(chatRoomID: String, accountFingerprint: String) async throws {
        clearedRoomIDs.append(chatRoomID)
        stored[chatRoomID] = nil
    }
}

/// Remembers what it was handed, because the point of the layer is *what* goes
/// into the call: the previous note plus only what has happened since, never the
/// whole history.
actor FakeSummaryWriter: ConversationSummaryWriter {
    private(set) var callCount = 0
    private(set) var requests: [ConversationSummaryRequest] = []
    private let answer: String?

    init(answer: String? = "지수와의 1:1. 존댓말로 대화함. 이번 주 저녁 약속을 잡는 중.") {
        self.answer = answer
    }

    func writeSummary(_ request: ConversationSummaryRequest) async throws -> ConversationSummaryResult {
        callCount += 1
        requests.append(request)
        guard let answer else { throw FakeSummaryError.unavailable }
        return ConversationSummaryResult(summary: answer, people: people)
    }

    /// What this writer claims to have learned about the people it was handed.
    /// Empty unless a test is about 사람 기억.
    var people: [PersonNoteUpdate] = []

    var lastRequest: ConversationSummaryRequest? { requests.last }

    enum FakeSummaryError: LocalizedError {
        case unavailable
        var errorDescription: String? { "Codex를 호출하지 못했습니다." }
    }
}

actor FakeReplyGenerator: ReplyGenerator {
    private(set) var callCount = 0
    private(set) var lastRequest: ReplyDraftRequest?
    private(set) var requests: [ReplyDraftRequest] = []
    /// One entry per call, the last one repeating for any calls beyond it.
    ///
    /// A list rather than a single value because 뒷말 대기 is now driven by what
    /// the model answers: a test about it has to say "flag it on the first call,
    /// not on the second" and could not with one fixed draft.
    private let drafts: [ReplyDraft?]

    init(draft: ReplyDraft? = ReplyDraft(shouldReply: true, mode: .directQuestion, confidence: .high, text: "네 좋아요")) {
        drafts = [draft]
    }

    init(drafts: [ReplyDraft?]) {
        self.drafts = drafts.isEmpty ? [nil] : drafts
    }

    func generateReply(_ request: ReplyDraftRequest) async throws -> ReplyDraft {
        callCount += 1
        lastRequest = request
        requests.append(request)
        guard let draft = drafts[min(callCount - 1, drafts.count - 1)] else {
            throw FakeError.unavailable
        }
        return draft
    }

    enum FakeError: LocalizedError {
        case unavailable
        var errorDescription: String? { "Codex를 호출하지 못했습니다." }
    }
}
