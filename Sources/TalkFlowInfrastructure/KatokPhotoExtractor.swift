import Foundation
import TalkFlowDomain

/// Takes the picture behind a photo message out of KakaoTalk's local media.
///
/// Only what this Mac already holds: `--no-cdn` keeps katok from reaching
/// KakaoTalk's servers for a photo that has aged out of the local cache. A
/// draft is not worth an outbound request to Kakao on the user's behalf, and a
/// missing picture costs one line of context while a slow download would cost
/// the reply.
///
/// Files land in a directory of their own so `discard` can remove the whole
/// call's worth at once.
public struct KatokPhotoExtractor: MessagePhotoSource {
    private let executableURL: URL?
    private let environment: KatokEnvironment

    public init(fileManager: FileManager = .default) {
        self.init(
            executableURL: KatokConnection.findExecutable(using: fileManager),
            environment: KatokEnvironment()
        )
    }

    init(executableURL: URL?, environment: KatokEnvironment = KatokEnvironment()) {
        self.executableURL = executableURL
        self.environment = environment
    }

    public func photos(for messages: [ChatMessage], in room: ChatRoom) async -> MessagePhotoSet {
        // Re-applied here rather than trusted from the caller: this is the side
        // that launches processes and writes files, and the cap is what keeps
        // both bounded.
        let candidates = MessagePhotoSelection.candidates(in: messages)
        guard let executableURL, !candidates.isEmpty else { return .none }

        let directoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "talkflow-photos-\(UUID().uuidString)")
        let created: ()? = try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        guard created != nil else { return .none }

        // The resolved account is passed for the same reason every other katok
        // call passes it: the connector derives its database from a cached id,
        // and after an account switch that is the wrong conversation's media.
        let processEnvironment = environment.katokProcessEnvironment()
        let extracted = await Task.detached {
            candidates.flatMap { message in
                extract(
                    message: message,
                    room: room,
                    into: directoryURL,
                    executableURL: executableURL,
                    processEnvironment: processEnvironment
                )
            }
        }.value

        // An empty directory is still a directory, and one per reply adds up.
        guard !extracted.isEmpty else {
            try? FileManager.default.removeItem(at: directoryURL)
            return .none
        }
        return MessagePhotoSet(directoryURL: directoryURL, photos: extracted)
    }

    public func discard(_ set: MessagePhotoSet) {
        guard let directoryURL = set.directoryURL else { return }
        try? FileManager.default.removeItem(at: directoryURL)
    }

    /// One message at a time, by log id.
    ///
    /// katok can also read "the newest N media in this room", which would be a
    /// single process launch instead of one per photo, but that answer is about
    /// the room rather than about these messages: if the archive has drifted
    /// behind KakaoTalk it returns a picture the model was never shown the text
    /// of. The prompt claims each attachment belongs to a named message, so the
    /// extraction has to be asked in those terms.
    private func extract(
        message: ChatMessage,
        room: ChatRoom,
        into directoryURL: URL,
        executableURL: URL,
        processEnvironment: [String: String]
    ) -> [MessagePhoto] {
        guard let logID = Self.logID(of: message) else { return [] }

        let result = CommandLineTool(executableURL: executableURL).run(
            arguments: [
                "media", "get",
                "--chat", room.id,
                "--log", logID,
                "--out", directoryURL.path,
                "--kind", "photo",
                "--no-cdn",
                "--json"
            ],
            environment: processEnvironment
        )

        // katok reports "nothing resolved" as an empty record list with a zero
        // exit code, so the records are what decides, not the status.
        guard let result, result.exitCode == 0,
              let report = try? JSONDecoder().decode(KatokMediaReport.self, from: Data(result.output.utf8))
        else {
            return []
        }

        return report.records
            .filter { $0.kind == "photo" }
            .compactMap { record in
                let fileURL = directoryURL.appending(path: (record.path as NSString).lastPathComponent)
                guard isReadableImage(fileURL) else { return nil }
                return MessagePhoto(messageID: message.id, fileURL: fileURL)
            }
    }

    /// A path katok reported is not yet a picture a provider can read. A stub
    /// tier can leave a zero-byte placeholder behind, and handing that to the
    /// model turns a missing photo into a failed reply.
    private func isReadableImage(_ url: URL) -> Bool {
        guard Self.imageExtensions.contains(url.pathExtension.lowercased()) else { return false }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return size > 0
    }

    /// Message ids are `<chatId>-<logId>`, and katok wants the log id.
    private static func logID(of message: ChatMessage) -> String? {
        let parts = message.id.split(separator: "-")
        guard parts.count >= 2,
              let logID = parts.last.map(String.init),
              logID.allSatisfy(\.isNumber)
        else {
            return nil
        }
        return logID
    }

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "bmp"]
}

private struct KatokMediaReport: Decodable {
    struct Record: Decodable {
        let kind: String
        let path: String
    }

    let records: [Record]
}
