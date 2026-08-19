import Foundation
import Testing
import TalkFlowDomain
@testable import TalkFlowInfrastructure

/// The extractor is driven by a stub in place of katok. The real command was
/// measured by hand (see PLATFORM-FINDINGS 7); what these tests hold onto is the
/// part TalkFlow owns — reading the report, finding the files it names, and
/// leaving nothing behind.
@Test
func extractedPhotosLandInOneDirectoryThatDiscardRemoves() async throws {
    let stub = try StubKatok(behaviour: .writesPhoto)
    defer { stub.destroy() }

    let set = await stub.extractor.photos(for: [photoMessage(logID: "555")], in: room)

    #expect(set.photos.count == 1)
    #expect(set.photos.first?.messageID == "\(room.id)-555")
    #expect(FileManager.default.fileExists(atPath: set.photos[0].fileURL.path))

    stub.extractor.discard(set)

    let directory = try #require(set.directoryURL)
    #expect(FileManager.default.fileExists(atPath: directory.path) == false)
}

/// katok answers "there was nothing here" with a zero exit code and an empty
/// record list, so the status cannot be what decides. A directory per reply
/// would otherwise pile up in the temporary folder.
@Test
func aMessageWithNoPictureLeavesNoDirectoryBehind() async throws {
    let stub = try StubKatok(behaviour: .reportsNothing)
    defer { stub.destroy() }

    let set = await stub.extractor.photos(for: [photoMessage(logID: "555")], in: room)

    #expect(set.isEmpty)
    #expect(set.directoryURL == nil)
}

/// A stub tier can leave a zero-byte placeholder where a picture should be.
/// Handing that to the provider turns a missing photo into a failed reply.
@Test
func anEmptyPlaceholderFileIsNotOfferedToTheModel() async throws {
    let stub = try StubKatok(behaviour: .writesEmptyFile)
    defer { stub.destroy() }

    #expect(await stub.extractor.photos(for: [photoMessage(logID: "555")], in: room).isEmpty)
}

/// Messages that are not photos never reach the command line: a feed notice has
/// no picture behind it, and the cap is what keeps one reply from launching a
/// process per message.
@Test
func onlyPhotosUpToTheCapAreEverAskedFor() async throws {
    let stub = try StubKatok(behaviour: .writesPhoto)
    defer { stub.destroy() }
    let messages = (1...5).map { photoMessage(logID: "10\($0)") }
        + [ChatMessage(
            id: "\(room.id)-999",
            chatRoomID: room.id,
            sender: ChatMember(id: "s1", displayName: "지수"),
            body: "",
            sentAt: Date(timeIntervalSince1970: 1_000_000),
            kind: .attachment
        )]

    let set = await stub.extractor.photos(for: messages, in: room)
    defer { stub.extractor.discard(set) }

    #expect(set.photos.count == MessagePhotoSelection.limit)
    #expect(set.photos.map(\.messageID) == (3...5).map { "\(room.id)-10\($0)" })
}

@Test
func withoutTheConnectorThereAreNoPhotosAndNoTemporaryFiles() async {
    let extractor = KatokPhotoExtractor(executableURL: nil)

    #expect(await extractor.photos(for: [photoMessage(logID: "555")], in: room).isEmpty)
}

// MARK: - Fixtures

private let room = ChatRoom(id: "18400000000000001", displayName: "가족", kind: .direct)

private func photoMessage(logID: String) -> ChatMessage {
    ChatMessage(
        id: "\(room.id)-\(logID)",
        chatRoomID: room.id,
        sender: ChatMember(id: "s1", displayName: "지수"),
        body: "사진",
        sentAt: Date(timeIntervalSince1970: 1_000_000),
        kind: .photo
    )
}

/// A shell script standing in for `katok media get`.
///
/// Reads the same `--out` and `--log` the real command takes and answers in the
/// same JSON shape, including the `_thumb` suffix `--no-cdn` produces — the file
/// name is not the log id, which is why the report has to be read rather than
/// guessed at.
private struct StubKatok {
    enum Behaviour {
        case writesPhoto
        case writesEmptyFile
        case reportsNothing
    }

    let directoryURL: URL
    let extractor: KatokPhotoExtractor

    init(behaviour: Behaviour) throws {
        directoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "talkflow-stub-katok-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let scriptURL = directoryURL.appending(path: "katok")
        try Data(Self.script(behaviour).utf8).write(to: scriptURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        extractor = KatokPhotoExtractor(executableURL: scriptURL)
    }

    func destroy() {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    private static func script(_ behaviour: Behaviour) -> String {
        let body = switch behaviour {
        case .writesPhoto:
            """
            printf 'not-really-a-jpeg' > "$out/${log}_thumb.jpg"
            printf '{"records":[{"kind":"photo","path":"%s/%s_thumb.jpg"}]}' "$out" "$log"
            """
        case .writesEmptyFile:
            """
            : > "$out/${log}_thumb.jpg"
            printf '{"records":[{"kind":"photo","path":"%s/%s_thumb.jpg"}]}' "$out" "$log"
            """
        case .reportsNothing:
            #"printf '{"records":[]}'"#
        }

        return """
        #!/bin/sh
        out=""
        log=""
        while [ $# -gt 0 ]; do
          case "$1" in
            --out) out="$2"; shift 2 ;;
            --log) log="$2"; shift 2 ;;
            *) shift ;;
          esac
        done
        \(body)
        """
    }
}
