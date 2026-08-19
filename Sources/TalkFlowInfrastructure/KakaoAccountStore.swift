import Foundation

/// Remembers which KakaoTalk account TalkFlow resolved, so the derivation that
/// identifies it runs once rather than on every read.
///
/// Kept with TalkFlow's other local state rather than in the Keychain, which stays
/// reserved for keys and tokens. Owner-only permissions all the same, and that
/// matters more than the filing does: this used to say the id "grants nothing on
/// its own", which is true of the id alone and false of the pair it belongs to.
/// The database filename *and* its SQLCipher key both come from
/// `(user_id, device uuid)` — see `KakaoKeyDerivation` — so the id beside the
/// device uuid is the secret protecting a KakaoTalk database at rest. It is
/// written here, never logged, and never committed.
struct KakaoAccountStore: Sendable {
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/TalkFlow/kakao-account.json")
    }

    struct Record: Equatable, Sendable {
        let userID: Int
        /// The database this id derives. Cached so that confirming the account
        /// is a filename comparison rather than another PBKDF2 pass.
        let databaseName: String
    }

    func stored() -> Record? {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode(Stored.self, from: data),
              let databaseName = stored.databaseName
        else {
            return nil
        }
        return Record(userID: stored.userID, databaseName: databaseName)
    }

    /// The id alone, for callers that will verify it themselves.
    func storedUserID() -> Int? {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode(Stored.self, from: data)
        else {
            return nil
        }
        return stored.userID
    }

    func save(userID: Int, databaseName: String) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(Stored(userID: userID, databaseName: databaseName))
        // Owner-only permissions rather than file protection: the protection
        // classes are an iOS concept and writing with them fails here, which
        // silently left the record unsaved and re-derived on every call.
        try data.write(to: fileURL, options: [.atomic])
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private struct Stored: Codable {
        let userID: Int
        /// Absent in files written before the name was cached; such a record is
        /// treated as unverified and re-derived once.
        let databaseName: String?

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case databaseName = "database_name"
        }
    }
}
