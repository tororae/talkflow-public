import Foundation
import Testing
@testable import TalkFlowInfrastructure

private func makeStore() -> (KakaoAccountStore, URL) {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "talkflow-account-\(UUID().uuidString)/kakao-account.json")
    return (KakaoAccountStore(fileURL: url), url)
}

/// The record failed to write for a while because the file was saved with an
/// iOS-only protection class. Nothing surfaced: the account was simply re-derived
/// on every call, at 100,000 PBKDF2 rounds a time.
@Test
func aSavedAccountReadsBackWithItsDatabaseName() throws {
    let (store, url) = makeStore()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    try store.save(userID: 100_000_001, databaseName: "abc123")

    #expect(store.stored() == KakaoAccountStore.Record(userID: 100_000_001, databaseName: "abc123"))
    #expect(store.storedUserID() == 100_000_001)
}

@Test
func theRecordFileIsOwnerOnly() throws {
    let (store, url) = makeStore()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    try store.save(userID: 1, databaseName: "abc")

    let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
    #expect(permissions == 0o600)
}

/// Records written before the name was cached still hold a usable id; they are
/// treated as unverified so the name gets derived and stored once.
@Test
func aRecordWithoutADatabaseNameIsTreatedAsUnverified() throws {
    let (store, url) = makeStore()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data(#"{"user_id":12345}"#.utf8).write(to: url)

    #expect(store.stored() == nil)
    #expect(store.storedUserID() == 12345)
}

@Test
func clearingRemovesTheRecord() throws {
    let (store, url) = makeStore()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try store.save(userID: 1, databaseName: "abc")

    store.clear()

    #expect(store.stored() == nil)
    #expect(store.storedUserID() == nil)
}
