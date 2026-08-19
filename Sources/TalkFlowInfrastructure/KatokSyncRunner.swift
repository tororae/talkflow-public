import Foundation
import TalkFlowDomain

public struct KatokSyncRunner: Sendable {
    private let executableURL: URL
    private let environment: KatokEnvironment

    public init?() {
        self.init(executableURL: KatokConnection.findExecutable())
    }

    init?(executableURL: URL?, environment: KatokEnvironment = KatokEnvironment()) {
        guard let executableURL else { return nil }
        self.executableURL = executableURL
        self.environment = environment
    }

    /// `detectedAt` is when the caller noticed the database move. It is passed in
    /// rather than taken here because the wait that separates the two happens
    /// above this type, and a sync that timed itself would report the one part of
    /// the delay that was never the problem.
    public func sync(detectedAt: Date? = nil) async throws -> KakaoSyncReport {
        let processEnvironment = environment.katokProcessEnvironment()
        guard let result = await Task.detached(operation: {
            CommandLineTool(executableURL: executableURL)
                .run(
                    arguments: ["sync", "--source", "macos", "--json", "--touched"],
                    environment: processEnvironment
                )
        }).value,
        result.exitCode == 0,
        let report = try? JSONDecoder().decode(KatokSyncPayload.self, from: Data(result.output.utf8))
        else {
            throw KatokSyncError.failed
        }

        return KakaoSyncReport(
            totalMessages: report.totalMessages,
            insertedMessages: report.insertedMessages,
            updatedMessages: report.updatedMessages,
            changedChatRoomIDs: report.touchedChats?.map(\.chatID) ?? [],
            detectedAt: detectedAt,
            synchronizedAt: Date()
        )
    }
}

private struct KatokSyncPayload: Decodable {
    let totalMessages: Int
    let insertedMessages: Int
    let updatedMessages: Int
    let touchedChats: [TouchedChat]?

    enum CodingKeys: String, CodingKey {
        case totalMessages = "total_messages"
        case insertedMessages = "inserted_messages"
        case updatedMessages = "updated_messages"
        case touchedChats = "touched_chats"
    }

    struct TouchedChat: Decodable {
        let chatID: String

        enum CodingKeys: String, CodingKey {
            case chatID = "chat_id"
        }
    }
}

private enum KatokSyncError: LocalizedError {
    case failed

    var errorDescription: String? {
        "카카오톡 대화 동기화에 실패했습니다."
    }
}
