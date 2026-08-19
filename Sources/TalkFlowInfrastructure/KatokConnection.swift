import Foundation
import TalkFlowDomain

/// Reads KakaoTalk's locally synchronized data through katok.
/// The helper is bundled with the distributed app; `scripts/install-katok.sh`
/// provides the same binary during development.
///
/// Live probes go through the CLI because only katok can prove that KakaoTalk's
/// encrypted database is readable. Bulk reads go through the archive, which is
/// indexed and answers in microseconds instead of seconds per process launch.
public struct KatokConnection: KakaoConnection {
    private let executableURL: URL?
    private let environment: KatokEnvironment
    /// A reference, so every copy of this value shares one lookup.
    private let nicknames = AccountNicknameCache()

    public init(fileManager: FileManager = .default) {
        self.init(
            executableURL: Self.findExecutable(using: fileManager),
            environment: KatokEnvironment()
        )
    }

    init(executableURL: URL?, environment: KatokEnvironment = KatokEnvironment()) {
        self.executableURL = executableURL
        self.environment = environment
    }

    public func status() async -> KakaoConnectionStatus {
        guard let executableURL else {
            return .unavailable(reason: "katok 실행 파일을 찾지 못했습니다. scripts/install-katok.sh를 실행하세요.")
        }

        let katokEnvironment = environment.katokProcessEnvironment()
        let report = await Task.detached {
            CommandLineTool(executableURL: executableURL)
                .run(
                    arguments: ["doctor", "--macos-probe", "--json"],
                    environment: katokEnvironment
                )
                .flatMap { try? JSONDecoder().decode(KatokDoctorReport.self, from: Data($0.output.utf8)) }
        }.value

        guard let macOS = report?.sourceAdapter.macOS else {
            return .unavailable(reason: "카카오톡 연결 진단을 실행하지 못했습니다.")
        }
        guard macOS.appInstalled else {
            return .unavailable(reason: "이 Mac에서 카카오톡을 찾지 못했습니다.")
        }
        guard macOS.containerPresent else {
            return .unavailable(reason: "카카오톡 로컬 데이터에 접근하지 못했습니다. 전체 디스크 접근 권한을 확인하세요.")
        }
        guard macOS.authCached, let profile = environment.accountProfile() else {
            return .unavailable(reason: "카카오톡 대화는 찾았지만 계정 확인을 마치지 못했습니다.")
        }
        if let drift = accountDriftReason() {
            return .unavailable(reason: drift)
        }
        return .connected(account: profile.named(nickname(for: profile.fingerprint)))
    }

    /// The account's own name travels with the account rather than being fetched
    /// where it is used. Every caller that has a verified account already has it,
    /// so deciding whether a message called this account costs no read at all.
    private func nickname(for fingerprint: String) -> String? {
        nicknames.nickname(forAccount: fingerprint) {
            try? KatokArchiveReader(environment: environment).accountNickname()
        }
    }

    /// Signing into a different KakaoTalk account leaves the old database in
    /// place and starts a new one. The connector derives one database name from
    /// a cached account id and cannot be pointed at another, so it keeps reading
    /// the account that was signed in when that cache was written.
    ///
    /// Reporting "connected" there would be worse than reporting nothing: replies
    /// would be drafted from one account's conversations and delivered by
    /// another's KakaoTalk.
    private func accountDriftReason() -> String? {
        let databases = environment.kakaoDatabases()
        guard databases.count > 1, let live = databases.map(\.modifiedAt).max() else { return nil }
        guard let reader = try? KatokArchiveReader(environment: environment),
              let newestArchived = try? reader.newestMessageDate()
        else {
            return nil
        }

        guard live.timeIntervalSince(newestArchived) > Self.acceptableDrift else { return nil }
        return """
        카카오톡 계정이 바뀐 것으로 보입니다. 읽고 있는 대화가 \(Self.dayCount(from: newestArchived))일 전에서 멈춰 있습니다. \
        지금 로그인된 계정의 대화를 읽으려면 연결 도구가 새 계정을 인식해야 합니다.
        """
    }

    /// A day of slack: KakaoTalk touches its database for reasons other than new
    /// messages, and a quiet account should not be reported as broken.
    private static let acceptableDrift: TimeInterval = 86_400

    private static func dayCount(from date: Date) -> Int {
        max(1, Int(Date().timeIntervalSince(date) / 86_400))
    }

    /// Asks KakaoTalk's own chat list which rooms it is showing.
    ///
    /// Read-only and takes no focus — measured 2.61s with the frontmost
    /// application unchanged throughout. It is the only source that knows
    /// anything about membership at all; the archive keeps a room forever once a
    /// message has arrived in it.
    ///
    /// Its limits are the list's, not this call's: only rows KakaoTalk has
    /// rendered, and names rather than ids. Both are why the caller may mark a
    /// room but never delete one on this evidence alone.
    public func openRoomWindowNames() async -> Set<String>? {
        let katokEnvironment = environment.katokProcessEnvironment()
        guard let list = await read(KatokWindowList.self, ["send", "--list-windows", "--json"], katokEnvironment)
        else {
            return nil
        }
        return Set(list.openWindows)
    }

    public func joinedRoomNames() async -> Set<String>? {
        guard let executableURL else { return nil }
        let katokEnvironment = environment.katokProcessEnvironment()

        async let listed = read(KatokRoomList.self, ["send", "--list-rooms", "--limit", "200", "--json"], katokEnvironment)
        async let open = openRoomWindowNames()

        // Two sources, and a room in either is one this account is certainly
        // still in. An open window is the stronger of the two — it is a window
        // that exists — and the chat list reaches rooms with no window open.
        let names = Self.trustworthyRoomNames(rooms: await listed?.rooms ?? []).union(await open ?? [])

        // An empty answer is not "every room is gone". KakaoTalk with nothing on
        // screen reports nothing, and reading that as a membership fact would
        // mark every configured room as left.
        return names.isEmpty ? nil : names
    }

    /// The chat list, when what came back is actually the chat list.
    ///
    /// Measured 2026-08-10: with six chat windows open, `--list-rooms` returned
    /// 58 rows that were all the same name — the message list inside the
    /// frontmost window, not the chat list. Taken at face value it would have
    /// marked every room but that one as no longer joined.
    ///
    /// A chat list has one row per chat. Repeats mean something else was read,
    /// and the whole answer is dropped rather than partly believed. Names can
    /// legitimately repeat across two rooms, so this refuses a little more than
    /// it must — which is the right direction, because refusing costs a marking
    /// nobody sees and believing costs a false accusation on every room.
    static func trustworthyRoomNames(rooms: [String]) -> Set<String> {
        guard !rooms.isEmpty else { return [] }
        let unique = Set(rooms)
        return unique.count == rooms.count ? unique : []
    }

    private func read<T: Decodable>(
        _ type: T.Type,
        _ arguments: [String],
        _ environment: [String: String]
    ) async -> T? {
        guard let executableURL else { return nil }
        let result = await Task.detached {
            CommandLineTool(executableURL: executableURL).run(
                arguments: arguments,
                environment: environment
            )
        }.value
        guard let result, result.exitCode == 0 else { return nil }
        return try? JSONDecoder().decode(T.self, from: Data(result.output.utf8))
    }

    public func chatRooms() async throws -> [ChatRoom] {
        try KatokArchiveReader(environment: environment).chatRooms()
    }

    public func recentMessages(in chatRoom: ChatRoom, limit: Int) async throws -> [ChatMessage] {
        try KatokArchiveReader(environment: environment)
            .recentMessages(chatRoomID: chatRoom.id, limit: limit)
    }

    /// Unlike the account-wide name this one is read every time it is asked for.
    ///
    /// The cache exists because the account-wide name is wanted on every status
    /// probe — before each sync and by every screen that opens — and each of
    /// those would otherwise scan for a message the account sent. A room's name
    /// is asked for once per judgement in one room, and costs a single indexed
    /// read against (chat_id, timestamp). Caching it would buy nothing, need a
    /// key per room, and hold a name the user has since changed in exactly the
    /// room where they bothered to change it.
    public func accountNickname(in chatRoom: ChatRoom) async -> String? {
        try? KatokArchiveReader(environment: environment)
            .accountNickname(chatRoomID: chatRoom.id)
    }

    public func forgetAccountNickname() async {
        nicknames.forget()
    }

    static func findExecutable(using fileManager: FileManager = .default) -> URL? {
        let bundled = Bundle.main.resourceURL?.appending(path: "katok")
        let candidates = [
            bundled?.path,
            "/opt/homebrew/bin/katok",
            "/usr/local/bin/katok"
        ].compactMap { $0 }

        return candidates
            .map(URL.init(fileURLWithPath:))
            .first { fileManager.isExecutableFile(atPath: $0.path) }
    }
}

private struct KatokRoomList: Decodable {
    let rooms: [String]
}

private struct KatokWindowList: Decodable {
    let openWindows: [String]

    enum CodingKeys: String, CodingKey {
        case openWindows = "open_windows"
    }
}

private struct KatokDoctorReport: Decodable {
    struct SourceAdapter: Decodable {
        struct MacOS: Decodable {
            let appInstalled: Bool
            let containerPresent: Bool
            let authCached: Bool

            enum CodingKeys: String, CodingKey {
                case appInstalled = "app_installed"
                case containerPresent = "container_present"
                case authCached = "auth_cached"
            }
        }

        let macOS: MacOS?

        enum CodingKeys: String, CodingKey {
            case macOS = "macos"
        }
    }

    let sourceAdapter: SourceAdapter

    enum CodingKeys: String, CodingKey {
        case sourceAdapter = "source_adapter"
    }
}
