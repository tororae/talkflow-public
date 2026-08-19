import Foundation
import GRDB
import Testing
import TalkFlowDomain
@testable import TalkFlowInfrastructure

private let account = "katok-test"
private let room = ChatRoom(id: "room-b", displayName: "프로젝트 팀", kind: .group)
private let noon = Date(timeIntervalSince1970: 1_770_000_000)

private func makeDatabase() throws -> (TalkFlowDatabase, URL, () -> Void) {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "talkflow-burning-\(UUID().uuidString)/talkflow.sqlite")
    let database = try TalkFlowDatabase(fileURL: url)
    return (database, url, { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) })
}

/// Every room configured before this existed has to keep answering exactly as it
/// did. An upgrade that quietly switched a room to burning would change what it
/// says in a room full of other people.
@Test
func aRoomFromBeforeBurningExistedReadsBackWithItOff() async throws {
    let (database, _, cleanup) = try makeDatabase()
    defer { cleanup() }

    let policy = try await RoomPolicyRepository(database: database)
        .policy(for: room, accountFingerprint: account)

    #expect(policy.burning.isEnabled == false)
    #expect(policy.burning == .off)
}

@Test
func burningSettingsSurviveReopeningTheStore() async throws {
    let (database, fileURL, cleanup) = try makeDatabase()
    defer { cleanup() }
    let repository = RoomPolicyRepository(database: database)

    var policy = try await repository.policy(for: room, accountFingerprint: account)
    policy.burning = BurningMode(
        isEnabled: true,
        chance: InterjectionChance(percent: 25),
        duration: JudgementInterval(shortest: 300, longest: 900),
        cooldown: JudgementInterval(shortest: 3_600, longest: 7_200),
        interjectionChance: InterjectionChance(percent: 85),
        minimumInterval: 15,
        judgementInterval: JudgementInterval(fixed: 5)
    )
    try await repository.save(policy)

    let reopened = try await RoomPolicyRepository(database: try TalkFlowDatabase(fileURL: fileURL))
        .policy(for: room, accountFingerprint: account)

    #expect(reopened.burning == policy.burning)
}

/// The reason this lives on disk at all is the cooldown, not the burn. A burn
/// lost to a restart costs a room a few talkative minutes; a cooldown lost to one
/// lets the room burn again the moment the app comes back, which is the single
/// thing the cooldown exists to prevent.
@Test
func aCooldownOutlivesTheApp() async throws {
    let (database, fileURL, cleanup) = try makeDatabase()
    defer { cleanup() }
    let state = BurningState(
        startedAt: noon,
        endsAt: noon.addingTimeInterval(600),
        cooldownUntil: noon.addingTimeInterval(4_200)
    )

    try await BurningStateRepository(database: database)
        .save(state, for: room.id, accountFingerprint: account)

    let reopened = try await BurningStateRepository(database: try TalkFlowDatabase(fileURL: fileURL))
        .state(for: room.id, accountFingerprint: account)

    #expect(reopened == state)
}

@Test
func aRoomThatHasNeverBurnedHasNoState() async throws {
    let (database, _, cleanup) = try makeDatabase()
    defer { cleanup() }

    let state = try await BurningStateRepository(database: database)
        .state(for: room.id, accountFingerprint: account)

    #expect(state == nil)
}

/// Said once. The room is examined on every sync, and a burn whose end was
/// already announced is not owed a second goodbye.
@Test
func announcingTheEndOfABurnIsRemembered() async throws {
    let (database, _, cleanup) = try makeDatabase()
    defer { cleanup() }
    let repository = BurningStateRepository(database: database)
    let state = BurningState(
        startedAt: noon,
        endsAt: noon.addingTimeInterval(600),
        cooldownUntil: noon.addingTimeInterval(4_200)
    )
    try await repository.save(state, for: room.id, accountFingerprint: account)

    #expect(try await repository.announcedAt(for: room.id, accountFingerprint: account) == nil)
    #expect(state.hasJustEnded(at: noon.addingTimeInterval(700), announcedAt: nil))

    try await repository.markAnnounced(
        at: noon.addingTimeInterval(605),
        for: room.id,
        accountFingerprint: account
    )
    let announced = try await repository.announcedAt(for: room.id, accountFingerprint: account)

    #expect(announced == noon.addingTimeInterval(605))
    #expect(!state.hasJustEnded(at: noon.addingTimeInterval(700), announcedAt: announced))
}

/// A new burn clears the previous one's announcement. Left behind it would read
/// as this burn's, and this burn would end without a word.
@Test
func aNewBurnDoesNotInheritTheLastOnesGoodbye() async throws {
    let (database, _, cleanup) = try makeDatabase()
    defer { cleanup() }
    let repository = BurningStateRepository(database: database)
    let first = BurningState(
        startedAt: noon,
        endsAt: noon.addingTimeInterval(600),
        cooldownUntil: noon.addingTimeInterval(4_200)
    )
    try await repository.save(first, for: room.id, accountFingerprint: account)
    try await repository.markAnnounced(
        at: noon.addingTimeInterval(605),
        for: room.id,
        accountFingerprint: account
    )

    let second = BurningState(
        startedAt: noon.addingTimeInterval(5_000),
        endsAt: noon.addingTimeInterval(5_600),
        cooldownUntil: noon.addingTimeInterval(9_200)
    )
    try await repository.save(second, for: room.id, accountFingerprint: account)

    #expect(try await repository.announcedAt(for: room.id, accountFingerprint: account) == nil)
}

/// A room with no burn on record has no end to have spoken about, and inserting
/// one here would invent a burn with no deadlines in it.
@Test
func announcingAgainstARoomThatNeverBurnedWritesNothing() async throws {
    let (database, _, cleanup) = try makeDatabase()
    defer { cleanup() }
    let repository = BurningStateRepository(database: database)

    try await repository.markAnnounced(at: noon, for: room.id, accountFingerprint: account)

    #expect(try await repository.state(for: room.id, accountFingerprint: account) == nil)
    #expect(try await repository.announcedAt(for: room.id, accountFingerprint: account) == nil)
}
