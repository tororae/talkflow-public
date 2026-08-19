import Foundation
import Testing
import TalkFlowDomain
@testable import TalkFlowApplication

private let account = AccountProfile(label: "카카오톡", fingerprint: "acct")
private let groupRoom = ChatRoom(id: "room-b", displayName: "프로젝트 팀", kind: .group)

/// Holds one room's cycle, and counts writes so a test can say a burn started
/// rather than only that the numbers changed.
private actor FakeBurningStore: BurningStateStore {
    private var stored: BurningState?
    private var announced: Date?
    private var hoursOpen: Bool?
    private(set) var saves = 0

    init(_ state: BurningState? = nil, hoursOpen: Bool? = nil) {
        stored = state
        self.hoursOpen = hoursOpen
    }

    func state(for chatRoomID: String, accountFingerprint: String) async throws -> BurningState? {
        stored
    }

    func save(_ state: BurningState, for chatRoomID: String, accountFingerprint: String) async throws {
        stored = state
        announced = nil
        saves += 1
    }

    func markAnnounced(at instant: Date, for chatRoomID: String, accountFingerprint: String) async throws {
        announced = instant
    }

    func announcedAt(for chatRoomID: String, accountFingerprint: String) async throws -> Date? {
        announced
    }

    func hoursWereOpen(for chatRoomID: String, accountFingerprint: String) async throws -> Bool? {
        hoursOpen
    }

    func recordHoursOpen(_ isOpen: Bool, for chatRoomID: String, accountFingerprint: String) async throws {
        hoursOpen = isOpen
    }
}

private func burningPolicy(
    chance: Int,
    hours: ReplyActiveHours = .always,
    burning: BurningMode
) -> RoomPolicy {
    RoomPolicy(
        accountFingerprint: account.fingerprint,
        chatRoomID: groupRoom.id,
        responseMode: .automatic,
        interjectionChance: InterjectionChance(percent: chance),
        minimumInterval: 0,
        activeHours: hours,
        burning: burning
    )
}

private func pipeline(
    policy: RoomPolicy,
    store: FakeBurningStore,
    roll: BurningRoll
) -> DraftRepliesForChangedRooms {
    DraftRepliesForChangedRooms(
        connection: FakeKakaoConnection(
            status: .connected(account: account),
            rooms: [groupRoom],
            messagesByRoom: [groupRoom.id: [
                ChatMessage(
                    id: "m1",
                    chatRoomID: groupRoom.id,
                    sender: ChatMember(id: "s1", displayName: "지수"),
                    body: "다들 언제 볼까요?",
                    sentAt: Date()
                )
            ]]
        ),
        policyStore: FakePolicyStore([policy]),
        settingsStore: FakeSettingsStore(),
        actionLog: FakeActionLog(),
        generator: FakeReplyGenerator(),
        burningStore: store,
        burningRoll: roll,
        pause: { _ in }
    )
}

/// The whole point of the feature: an answer can start a burn, and the burn is
/// written down rather than held in memory, because a cooldown that vanishes on
/// restart lets a room burn again the moment the app comes back.
@Test
func ananswerCanStartABurnAndTheBurnIsWrittenDown() async throws {
    let store = FakeBurningStore()
    let policy = burningPolicy(
        chance: 100,
        burning: BurningMode(isEnabled: true, chance: InterjectionChance(percent: 100))
    )

    _ = await pipeline(policy: policy, store: store, roll: .always)(
        changedChatRoomIDs: [groupRoom.id]
    )

    #expect(await store.saves == 1)
    #expect(try await store.state(for: groupRoom.id, accountFingerprint: account.fingerprint) != nil)
}

/// The switch is the consent, exactly as it is for 먼저 말 걸기. A room that never
/// turned burning on must not acquire a cycle because the draw happened to land.
@Test
func aRoomWithBurningOffNeverStartsOneHoweverTheDrawLands() async throws {
    let store = FakeBurningStore()
    let policy = burningPolicy(
        chance: 100,
        burning: BurningMode(isEnabled: false, chance: InterjectionChance(percent: 100))
    )

    _ = await pipeline(policy: policy, store: store, roll: .always)(
        changedChatRoomIDs: [groupRoom.id]
    )

    #expect(await store.saves == 0)
}

@Test
func adrawThatMissesLeavesTheRoomAsItWas() async throws {
    let store = FakeBurningStore()
    let policy = burningPolicy(
        chance: 100,
        burning: BurningMode(isEnabled: true, chance: InterjectionChance(percent: 50))
    )

    _ = await pipeline(policy: policy, store: store, roll: .never)(
        changedChatRoomIDs: [groupRoom.id]
    )

    #expect(await store.saves == 0)
}

/// 답변 활성화 시간 closing has to actually end a burn, not merely outrank it. The
/// room answers nothing either way while the hours are shut, so leaving the burn
/// running looks identical today and wrong tomorrow — it would still be running
/// when the hours reopened, and the room would come back talkative for reasons
/// nobody could see.
@Test
func closingHoursEndTheBurnRatherThanWaitingItOut() async throws {
    let now = Date()
    let live = BurningState(
        startedAt: now.addingTimeInterval(-60),
        endsAt: now.addingTimeInterval(3_600),
        cooldownUntil: now.addingTimeInterval(10_000)
    )
    let store = FakeBurningStore(live)
    // A window that cannot contain the present instant, whatever time the test
    // runs at: one minute wide, ninety minutes ago.
    let minutes = Calendar.current.component(.hour, from: now) * 60
        + Calendar.current.component(.minute, from: now)
    let start = (minutes + 1_350) % 1_440
    let policy = burningPolicy(
        chance: 100,
        hours: ReplyActiveHours(isLimited: true, startMinute: start, endMinute: (start + 1) % 1_440),
        burning: BurningMode(isEnabled: true)
    )

    _ = await pipeline(policy: policy, store: store, roll: .never)(
        changedChatRoomIDs: [groupRoom.id]
    )
    // Read after the run rather than `now` plus a second of slack. The burn is
    // ended at the pipeline's own instant, so asking at `now + 1` asserts that
    // the pipeline took under a second — measured 2026-08-19, it takes 1.2s to
    // 1.4s under a loaded parallel suite and the burn then reads as still live.
    // The claim is that the burn was over by the time the run returned, and this
    // is that claim with no clock slack in it.
    let ranAt = Date()

    let after = try await store.state(for: groupRoom.id, accountFingerprint: account.fingerprint)
    #expect(after?.isBurning(at: ranAt) == false)
    #expect(after?.cooldownUntil == live.cooldownUntil)
}

/// The goodbye that burn was owed cannot go out inside closed hours, and left
/// unspoken it would arrive at the reopening as a farewell for a burn that ended
/// the night before.
@Test
func aBurnEndedByClosingHoursIsNotOwedAGoodbyeLater() async throws {
    let now = Date()
    let live = BurningState(
        startedAt: now.addingTimeInterval(-60),
        endsAt: now.addingTimeInterval(3_600),
        cooldownUntil: now.addingTimeInterval(10_000)
    )
    let store = FakeBurningStore(live)
    let minutes = Calendar.current.component(.hour, from: now) * 60
        + Calendar.current.component(.minute, from: now)
    let start = (minutes + 1_350) % 1_440
    let policy = burningPolicy(
        chance: 100,
        hours: ReplyActiveHours(isLimited: true, startMinute: start, endMinute: (start + 1) % 1_440),
        burning: BurningMode(isEnabled: true)
    )

    _ = await pipeline(policy: policy, store: store, roll: .never)(
        changedChatRoomIDs: [groupRoom.id]
    )

    let announced = try await store.announcedAt(
        for: groupRoom.id,
        accountFingerprint: account.fingerprint
    )
    #expect(announced != nil)
}

/// Crossing the boundary is what fires it, and the phase has to be written even
/// when nothing is said — it records where the room was, not what was announced.
/// Skipping the write on a quiet room leaves the boundary uncrossed and fires the
/// greeting at some unrelated hour days later.
@Test
func theHoursPhaseIsRecordedOnEveryPass() async throws {
    let now = Date()
    let minutes = Calendar.current.component(.hour, from: now) * 60
        + Calendar.current.component(.minute, from: now)
    let start = (minutes + 1_350) % 1_440
    let store = FakeBurningStore()
    let policy = burningPolicy(
        chance: 100,
        hours: ReplyActiveHours(isLimited: true, startMinute: start, endMinute: (start + 1) % 1_440),
        burning: BurningMode(isEnabled: false)
    )

    _ = await pipeline(policy: policy, store: store, roll: .never)(
        changedChatRoomIDs: [groupRoom.id]
    )

    // Outside its window, so the pass recorded closed.
    #expect(try await store.hoursWereOpen(for: groupRoom.id, accountFingerprint: account.fingerprint) == false)
}

/// A room seen for the first time has not crossed anything. Reading a missing
/// phase as closed would greet every room once, on the first sync after this
/// shipped.
@Test
func aRoomSeenForTheFirstTimeAnnouncesNothing() async throws {
    let now = Date()
    let minutes = Calendar.current.component(.hour, from: now) * 60
        + Calendar.current.component(.minute, from: now)
    let store = FakeBurningStore(nil, hoursOpen: nil)
    var policy = burningPolicy(
        chance: 100,
        // A window that contains now, so this pass sees the room as open.
        hours: ReplyActiveHours(isLimited: true, startMinute: (minutes + 1_439) % 1_440, endMinute: (minutes + 60) % 1_440),
        burning: BurningMode(isEnabled: false)
    )
    policy.announcements = StateAnnouncements(
        transitions: [.activeHoursOpened, .activeHoursClosed],
        withinRecentConversation: 3_600,
        delivery: .draftOnly
    )
    let log = FakeActionLog()

    let actions = await DraftRepliesForChangedRooms(
        connection: FakeKakaoConnection(
            status: .connected(account: account),
            rooms: [groupRoom],
            messagesByRoom: [groupRoom.id: [
                ChatMessage(
                    id: "m1",
                    chatRoomID: groupRoom.id,
                    sender: ChatMember(id: "s1", displayName: "지수"),
                    body: "다들 언제 볼까요?",
                    sentAt: now
                )
            ]]
        ),
        policyStore: FakePolicyStore([policy]),
        settingsStore: FakeSettingsStore(),
        actionLog: log,
        generator: FakeReplyGenerator(),
        burningStore: store,
        burningRoll: .never,
        pause: { _ in }
    )(changedChatRoomIDs: [groupRoom.id])

    #expect(!actions.contains { $0.detail.contains("답변 시간") })
    #expect(try await store.hoursWereOpen(for: groupRoom.id, accountFingerprint: account.fingerprint) == true)
}

/// Silence has to be legible. The first burn to run in a real room ended, the
/// end was marked as announced, and no row appeared anywhere — from outside
/// there was no telling a model that chose to stay quiet from a call that
/// failed. Declines are hundreds a day on the reply path and a handful a day
/// here, so recording one buries nothing.
@Test
func anAnnouncementThatSaysNothingStillLeavesARow() async throws {
    let now = Date()
    let ended = BurningState(
        startedAt: now.addingTimeInterval(-600),
        endsAt: now.addingTimeInterval(-1),
        cooldownUntil: now.addingTimeInterval(3_600)
    )
    let store = FakeBurningStore(ended)
    var policy = burningPolicy(chance: 100, burning: BurningMode(isEnabled: true))
    policy.announcements = StateAnnouncements(
        transitions: [.burningEnded],
        withinRecentConversation: 3_600,
        delivery: .draftOnly
    )
    let log = FakeActionLog()

    _ = await DraftRepliesForChangedRooms(
        connection: FakeKakaoConnection(
            status: .connected(account: account),
            rooms: [groupRoom],
            messagesByRoom: [groupRoom.id: [
                ChatMessage(
                    id: "m1",
                    chatRoomID: groupRoom.id,
                    sender: ChatMember(id: "s1", displayName: "지수"),
                    body: "다들 언제 볼까요?",
                    sentAt: now
                )
            ]]
        ),
        policyStore: FakePolicyStore([policy]),
        settingsStore: FakeSettingsStore(),
        actionLog: log,
        generator: FakeReplyGenerator(draft: ReplyDraft(
            shouldReply: false,
            mode: .spontaneous,
            confidence: .medium,
            text: nil,
            declineReason: "지금 꺼낼 말이 없습니다"
        )),
        burningStore: store,
        burningRoll: .never,
        pause: { _ in }
    )(changedChatRoomIDs: [groupRoom.id])

    let recorded = await log.recorded
    #expect(recorded.contains { $0.detail.contains("집중 종료 알림") })
}
