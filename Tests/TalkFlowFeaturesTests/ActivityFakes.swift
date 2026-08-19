import Foundation
import TalkFlowApplication
import TalkFlowDomain

let testAccount = AccountProfile(label: "테스트", fingerprint: "katok-test")

/// The run is nil by default, which is how every row written before it was
/// recorded reads. The screen has to keep working from the trigger line alone
/// for those.
func testAction(
    id: Int64,
    kind: AgentAction.Kind,
    roomID: String = "room-a",
    roomName: String = "가족",
    triggerMessageID: String? = nil,
    triggerText: String? = "언제 와?",
    replyMode: ReplyTrigger? = nil,
    replyText: String? = nil,
    run: AnsweredRun? = nil,
    minutesAgo: Int = 0
) -> AgentAction {
    AgentAction(
        id: id,
        accountFingerprint: testAccount.fingerprint,
        chatRoomID: roomID,
        chatRoomName: roomName,
        kind: kind,
        triggerMessageID: triggerMessageID ?? "m\(id)",
        triggerText: triggerText,
        triggerSenderName: "지수",
        answeredRun: run,
        replyMode: replyMode,
        replyText: replyText,
        detail: "기록",
        createdAt: Date(timeIntervalSince1970: 1_000_000 - Double(minutesAgo) * 60)
    )
}

func testDraft(
    id: Int64,
    roomID: String = "room-a",
    roomName: String = "가족",
    replyText: String = "곧 도착해요",
    minutesAgo: Int = 0
) -> AgentAction {
    testAction(
        id: id,
        kind: .drafted,
        roomID: roomID,
        roomName: roomName,
        replyText: replyText,
        minutesAgo: minutesAgo
    )
}

/// Mirrors the repository's pending rule closely enough to test the screen
/// against it: a draft is resolved by a later send or dismissal of the same
/// trigger, and never by a failure.
actor FakeActionLog: AgentActionLog {
    private(set) var recorded: [AgentAction] = []
    private var nextID: Int64

    init(_ existing: [AgentAction] = []) {
        recorded = existing
        nextID = (existing.map(\.id).max() ?? 0) + 1
    }

    func record(_ action: AgentAction) async throws {
        var stored = action
        stored.id = nextID
        nextID += 1
        recorded.append(stored)
    }

    func recent(limit: Int) async throws -> [AgentAction] {
        Array(sortedNewestFirst(recorded).prefix(limit))
    }

    func recent(chatRoomID: String, limit: Int) async throws -> [AgentAction] {
        Array(sortedNewestFirst(recorded.filter { $0.chatRoomID == chatRoomID }).prefix(limit))
    }

    func lastReplyDate(chatRoomID: String, accountFingerprint: String) async throws -> Date? {
        nil
    }

    func lastJudgementDate(chatRoomID: String, accountFingerprint: String) async throws -> Date? {
        nil
    }

    func hasAction(chatRoomID: String, triggerMessageID: String) async throws -> Bool {
        recorded.contains { $0.chatRoomID == chatRoomID && $0.triggerMessageID == triggerMessageID }
    }

    func openerCount(chatRoomID: String, accountFingerprint: String, since: Date) async throws -> Int {
        recorded.filter {
            $0.chatRoomID == chatRoomID
                && $0.accountFingerprint == accountFingerprint
                && $0.kind == .opened
                && $0.createdAt > since
        }.count
    }

    func pendingDrafts(limit: Int) async throws -> [AgentAction] {
        let resolved = Set(
            recorded
                .filter { $0.kind == .sent || $0.kind == .dismissed }
                .map(Self.triggerKey)
        )
        let pending = recorded.filter {
            $0.kind == .drafted && $0.replyText != nil && !resolved.contains(Self.triggerKey($0))
        }
        return Array(sortedNewestFirst(pending).prefix(limit))
    }

    func dismissDraft(id: Int64) async throws {
        guard let draft = recorded.first(where: { $0.id == id }) else { return }
        try await record(
            AgentAction(
                accountFingerprint: draft.accountFingerprint,
                chatRoomID: draft.chatRoomID,
                chatRoomName: draft.chatRoomName,
                kind: .dismissed,
                triggerMessageID: draft.triggerMessageID,
                detail: "사용자가 초안을 무시했습니다."
            )
        )
    }

    private func sortedNewestFirst(_ actions: [AgentAction]) -> [AgentAction] {
        actions.sorted { ($0.createdAt, $0.id) > ($1.createdAt, $1.id) }
    }

    private static func triggerKey(_ action: AgentAction) -> String {
        "\(action.chatRoomID)|\(action.triggerMessageID ?? "")"
    }

    func replyCountsBySender(
        chatRoomID: String,
        accountFingerprint: String
    ) async throws -> [(senderID: String, displayName: String, count: Int)] { [] }

}

struct FakeKakaoConnection: KakaoConnection {
    var statusValue: KakaoConnectionStatus = .connected(account: testAccount)
    var rooms: [ChatRoom] = []
    var messagesByRoom: [String: [ChatMessage]] = [:]

    func status() async -> KakaoConnectionStatus { statusValue }
    func chatRooms() async throws -> [ChatRoom] { rooms }

    func recentMessages(in chatRoom: ChatRoom, limit: Int) async throws -> [ChatMessage] {
        Array((messagesByRoom[chatRoom.id] ?? []).suffix(limit))
    }
}

enum FakeStoreError: LocalizedError {
    case unavailable

    var errorDescription: String? { "설정 저장소를 열지 못했습니다." }
}

/// Remembers what it was told, so a test can save and read back rather than
/// assert against the model's own copy of what it thinks it saved. The failure
/// counts make the first n calls throw and the rest succeed, which is what a
/// store that was briefly unavailable looks like.
actor FakeSettingsStore: AppSettingsStore {
    private var style: ResponseStyle
    private var condition: AnsweringCondition
    private var enabled = false
    private var launches = false
    private var accepted: Bool
    private var wakes = true
    private var model: AIModelChoice
    private var loadFailures: Int
    private var saveFailures: Int

    init(
        style: ResponseStyle = ResponseStyle(),
        condition: AnsweringCondition = .empty,
        usePolicyAccepted: Bool = false,
        model: AIModelChoice = .codexDefault,
        loadFailures: Int = 0,
        saveFailures: Int = 0
    ) {
        self.style = style
        self.condition = condition
        accepted = usePolicyAccepted
        self.model = model
        self.loadFailures = loadFailures
        self.saveFailures = saveFailures
    }

    func responseStyle() async throws -> ResponseStyle {
        if loadFailures > 0 {
            loadFailures -= 1
            throw FakeStoreError.unavailable
        }
        return style
    }

    func save(_ style: ResponseStyle) async throws {
        if saveFailures > 0 {
            saveFailures -= 1
            throw FakeStoreError.unavailable
        }
        self.style = style
    }

    /// Shares the failure counts with the style, because the screen saves both
    /// under one button: a store that drops one write and takes the other is not
    /// a failure this app can have.
    func answeringCondition() async throws -> AnsweringCondition {
        if loadFailures > 0 {
            loadFailures -= 1
            throw FakeStoreError.unavailable
        }
        return condition
    }

    func save(_ condition: AnsweringCondition) async throws {
        if saveFailures > 0 {
            saveFailures -= 1
            throw FakeStoreError.unavailable
        }
        self.condition = condition
    }

    func globalResponsesEnabled() async throws -> Bool { enabled }
    func setGlobalResponsesEnabled(_ enabled: Bool) async throws { self.enabled = enabled }
    func launchesAtLogin() async throws -> Bool { launches }
    func setLaunchesAtLogin(_ enabled: Bool) async throws { launches = enabled }
    func sendUsePolicyAccepted() async throws -> Bool { accepted }
    func setSendUsePolicyAccepted(_ accepted: Bool) async throws { self.accepted = accepted }
    func wakesDisplayToSend() async throws -> Bool { wakes }
    func setWakesDisplayToSend(_ enabled: Bool) async throws { wakes = enabled }
    func aiModel() async throws -> AIModelChoice { model }
    func setAIModel(_ choice: AIModelChoice) async throws { model = choice }
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
