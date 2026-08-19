import Foundation
import Testing
@testable import TalkFlowInfrastructure

private let databaseName = String(repeating: "a1b2", count: 19) + "cc"
private let otherDatabaseName = String(repeating: "f0e1", count: 19) + "dd"

private func makeContainer(_ names: [String]) throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "kakao-container-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    for name in names {
        try Data("x".utf8).write(to: url.appending(path: name))
    }
    return url
}

/// Signing into a second KakaoTalk account leaves both databases in place, and
/// that is the only signal TalkFlow gets that it may be reading the wrong one.
@Test
func twoAccountDatabasesAreBothReported() throws {
    let container = try makeContainer([databaseName, otherDatabaseName])
    defer { try? FileManager.default.removeItem(at: container) }

    let found = KatokEnvironment().kakaoDatabases(containerURL: container)

    #expect(found.count == 2)
}

@Test
func journalsAndUnrelatedFilesAreNotCountedAsDatabases() throws {
    let container = try makeContainer([
        databaseName,
        "\(databaseName)-wal",
        "\(databaseName)-shm",
        "Emoticon",
        String(repeating: "z", count: 78)
    ])
    defer { try? FileManager.default.removeItem(at: container) }

    let found = KatokEnvironment().kakaoDatabases(containerURL: container)

    #expect(found.count == 1)
    #expect(found.first?.url.lastPathComponent == databaseName)
}

@Test
func aMissingContainerReportsNoDatabasesRatherThanFailing() {
    let found = KatokEnvironment().kakaoDatabases(
        containerURL: URL(fileURLWithPath: "/nonexistent/kakao")
    )

    #expect(found.isEmpty)
}
