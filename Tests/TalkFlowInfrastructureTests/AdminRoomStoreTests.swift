import Foundation
import Testing
import TalkFlowDomain
@testable import TalkFlowInfrastructure

private func makeDatabase() throws -> (TalkFlowDatabase, () -> Void) {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "talkflow-admin-\(UUID().uuidString)/talkflow.sqlite")
    let database = try TalkFlowDatabase(fileURL: url)
    return (database, { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) })
}

@Test
func aRoomIsNotAConsoleUntilItIsDesignated() async throws {
    let (database, cleanup) = try makeDatabase()
    defer { cleanup() }
    let store = AdminRoomRepository(database: database)

    #expect(try await store.adminRoomIDs(accountFingerprint: "acct").isEmpty)
}

@Test
func designatingAndClearingARoomRoundTrips() async throws {
    let (database, cleanup) = try makeDatabase()
    defer { cleanup() }
    let store = AdminRoomRepository(database: database)

    try await store.setAdminRoom(true, chatRoomID: "room-1", accountFingerprint: "acct")
    #expect(try await store.adminRoomIDs(accountFingerprint: "acct") == ["room-1"])

    try await store.setAdminRoom(false, chatRoomID: "room-1", accountFingerprint: "acct")
    #expect(try await store.adminRoomIDs(accountFingerprint: "acct").isEmpty)
}

@Test
func designatingTheSameRoomTwiceIsNotAnError() async throws {
    let (database, cleanup) = try makeDatabase()
    defer { cleanup() }
    let store = AdminRoomRepository(database: database)

    try await store.setAdminRoom(true, chatRoomID: "room-1", accountFingerprint: "acct")
    try await store.setAdminRoom(true, chatRoomID: "room-1", accountFingerprint: "acct")
    #expect(try await store.adminRoomIDs(accountFingerprint: "acct") == ["room-1"])
}

@Test
func consolesAreScopedToTheAccountThatSetThem() async throws {
    let (database, cleanup) = try makeDatabase()
    defer { cleanup() }
    let store = AdminRoomRepository(database: database)

    try await store.setAdminRoom(true, chatRoomID: "room-1", accountFingerprint: "acct-a")
    #expect(try await store.adminRoomIDs(accountFingerprint: "acct-b").isEmpty)
    #expect(try await store.adminRoomIDs(accountFingerprint: "acct-a") == ["room-1"])
}
