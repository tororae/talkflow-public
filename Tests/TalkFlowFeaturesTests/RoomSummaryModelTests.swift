import Foundation
import Testing
import TalkFlowApplication
import TalkFlowDomain
@testable import TalkFlowFeatures

private let room = ChatRoom(id: "room-g", displayName: "달빛 스튜디오", kind: .group)

/// Remembers what the room screen wrote, so a test reads the store back rather
/// than trusting the model's own copy of what it thinks it saved.
///
/// A locked class rather than an actor because a test seeds it before the model
/// exists, where nothing can be awaited.
private final class FakeSummaryStore: ConversationSummaryStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String: ConversationSummary] = [:]

    func preload(_ summary: ConversationSummary) {
        lock.withLock { stored[summary.chatRoomID] = summary }
    }

    func saved(_ chatRoomID: String) -> ConversationSummary? {
        lock.withLock { stored[chatRoomID] }
    }

    func summary(for room: ChatRoom, accountFingerprint: String) async throws -> ConversationSummary? {
        saved(room.id)
    }

    func summaries(accountFingerprint: String) async throws -> [String: ConversationSummary] {
        lock.withLock { stored }
    }

    func save(_ summary: ConversationSummary) async throws {
        preload(summary)
    }

    func clear(chatRoomID: String, accountFingerprint: String) async throws {
        lock.withLock { stored[chatRoomID] = nil }
    }
}

private struct FakeSummaryWriter: ConversationSummaryWriter {
    var answer: String?

    func writeSummary(_ request: ConversationSummaryRequest) async throws -> ConversationSummaryResult {
        guard let answer else { throw ConversationSummaryError.refreshFailed }
        return ConversationSummaryResult(summary: answer)
    }
}

@MainActor
private func makeModel(
    store: FakeSummaryStore = FakeSummaryStore(),
    writerAnswer: String? = "달빛 스튜디오. 프로젝트 일정 이야기 중.",
    messages: [ChatMessage] = [roomMessage("m41")]
) -> RoomSummaryModel {
    RoomSummaryModel(
        manage: ManageConversationSummary(
            connection: FakeKakaoConnection(
                rooms: [room],
                messagesByRoom: [room.id: messages]
            ),
            summaryStore: store,
            writer: FakeSummaryWriter(answer: writerAnswer)
        )
    )
}

private func roomMessage(_ id: String) -> ChatMessage {
    ChatMessage(
        id: id,
        chatRoomID: room.id,
        sender: ChatMember(id: "s1", displayName: "지수"),
        body: "발표 자료 언제까지 필요해요?",
        sentAt: Date(timeIntervalSince1970: 1_700_000_100)
    )
}

private func summary(_ text: String, isPinned: Bool = false) -> ConversationSummary {
    ConversationSummary(
        accountFingerprint: testAccount.fingerprint,
        chatRoomID: room.id,
        text: text,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        isPinned: isPinned,
        coveredThroughMessageID: "m40",
        coveredMessageCount: 40
    )
}

@Test @MainActor
func aRoomWithNoSummaryShowsNothingRatherThanAnEmptyOne() async {
    let model = makeModel()

    await model.load(room)

    #expect(model.summary == nil)
    #expect(model.issue == nil)
}

/// The correction reaches disk, and it does not pin the room on its way there.
/// Typing used to set the flag that stopped the sweep, which made fixing one word
/// a decision to freeze the note — 고정 is a checkbox now.
@Test @MainActor
func anEditIsSavedWithoutPinningTheRoom() async {
    let store = FakeSummaryStore()
    store.preload(summary("프로젝트 팀 대화."))
    let model = makeModel(store: store)
    await model.load(room)

    model.edit("前 직장 동료들. 존댓말 유지.", in: room)

    #expect(await eventuallyTrue { store.saved(room.id)?.text == "前 직장 동료들. 존댓말 유지." })
    #expect(store.saved(room.id)?.isPinned == false)
    // The anchor survives, so the next refresh does not re-read history already
    // folded in.
    #expect(store.saved(room.id)?.coveredThroughMessageID == "m40")
}

/// Refused rather than shortened, like 답변 조건: a field that rewrites itself
/// mid-sentence is what made the keyword box impossible to type into.
@Test @MainActor
func anOverlongEditIsRefusedWithAReasonAndNeverStored() async {
    let store = FakeSummaryStore()
    store.preload(summary("프로젝트 팀 대화."))
    let model = makeModel(store: store)
    await model.load(room)

    model.edit(String(repeating: "가", count: ConversationSummary.characterLimit + 1), in: room)
    await Task.yield()

    #expect(model.issue != nil)
    #expect(store.saved(room.id)?.text == "프로젝트 팀 대화.")
}

/// 지금 갱신 on a pinned note changes nothing and says so on the screen. A button
/// that appears to work and quietly does nothing is the worse of the two.
@Test @MainActor
func theRefreshButtonRefusesAPinnedNoteWithAReasonOnScreen() async {
    let store = FakeSummaryStore()
    store.preload(summary("前 직장 동료들. 존댓말 유지.", isPinned: true))
    let model = makeModel(store: store, writerAnswer: "前 직장 동료들. 존댓말 유지. 발표 준비 중.")
    await model.load(room)

    await model.refresh(room)

    #expect(model.summary?.text == "前 직장 동료들. 존댓말 유지.")
    #expect(model.summary?.isPinned == true)
    #expect(model.issue != nil)
}

/// And the same button on an unpinned note rewrites it, edited or not.
@Test @MainActor
func theRefreshButtonRewritesANoteThatIsNotPinned() async {
    let store = FakeSummaryStore()
    store.preload(summary("前 직장 동료들. 존댓말 유지."))
    let model = makeModel(store: store, writerAnswer: "前 직장 동료들. 존댓말 유지. 발표 준비 중.")
    await model.load(room)

    await model.refresh(room)

    #expect(model.summary?.text == "前 직장 동료들. 존댓말 유지. 발표 준비 중.")
    #expect(model.issue == nil)
}

/// The checkbox, and it survives to disk on its own without a 저장 press — the
/// sweep may arrive while the user is still reading the sentence they protected.
@Test @MainActor
func theCheckboxPinsImmediatelyAndUnpinsAgain() async {
    let store = FakeSummaryStore()
    store.preload(summary("프로젝트 팀 대화."))
    let model = makeModel(store: store)
    await model.load(room)

    await model.setPinned(true, in: room)

    #expect(store.saved(room.id)?.isPinned == true)
    #expect(model.summary?.isPinned == true)
    #expect(store.saved(room.id)?.text == "프로젝트 팀 대화.")

    await model.setPinned(false, in: room)

    #expect(store.saved(room.id)?.isPinned == false)
    #expect(model.summary?.isPinned == false)
}

/// A model call can fail, and the button spends money — a press that silently does
/// nothing reads as a broken screen.
@Test @MainActor
func aFailedRefreshSaysSoAndLeavesTheNoteAlone() async {
    let store = FakeSummaryStore()
    store.preload(summary("프로젝트 팀 대화."))
    let model = makeModel(store: store, writerAnswer: nil)
    await model.load(room)

    await model.refresh(room)

    #expect(model.issue != nil)
    #expect(model.summary?.text == "프로젝트 팀 대화.")
    #expect(store.saved(room.id)?.text == "프로젝트 팀 대화.")
}

@Test @MainActor
func clearingLeavesNothingOnScreenOrOnDisk() async {
    let store = FakeSummaryStore()
    store.preload(summary("프로젝트 팀 대화."))
    let model = makeModel(store: store)
    await model.load(room)

    await model.clear(room)

    #expect(model.summary == nil)
    #expect(store.saved(room.id) == nil)
}

/// The edit saves in a task of its own, so a test has to give that task a turn
/// before it reads the store back. Yielding on the main actor is what hands the
/// turn over: that is where the model queued the work.
@MainActor
/// Bounded by a deadline rather than by a count of yields — see the note on
/// `eventually` in `SettingsModelTests`. A hundred yields is a hundred chances
/// that the scheduler runs the other task, which under a loaded parallel suite
/// is not the same as waiting for it.
private func eventuallyTrue(_ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock().now + .seconds(2)
    while ContinuousClock().now < deadline {
        if condition() { return true }
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(1))
    }
    return condition()
}
