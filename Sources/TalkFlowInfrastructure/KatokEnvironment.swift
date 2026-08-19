import CryptoKit
import Foundation
import TalkFlowDomain

/// Locates katok's on-disk state and derives TalkFlow's account identity from it.
///
/// katok owns this directory. TalkFlow only reads it, and never copies the raw
/// account identifier anywhere: everything outside this type sees the hashed
/// fingerprint instead.
struct KatokEnvironment: Sendable {
    struct AccountIdentity: Sendable {
        /// The sender id KakaoTalk stamps on messages this account sent.
        let senderID: String
        let fingerprint: String
    }

    let dataDirectoryURL: URL

    init(dataDirectoryURL: URL = KatokEnvironment.defaultDataDirectoryURL()) {
        self.dataDirectoryURL = dataDirectoryURL
    }

    var archiveURL: URL {
        dataDirectoryURL.appending(path: "archive.sqlite3")
    }

    var authCacheURL: URL {
        dataDirectoryURL.appending(path: "kakao/auth.json")
    }

    /// The resolved account wins over the connector's cache. The cache holds
    /// whichever account was signed in when it was written, and after a switch
    /// that is the wrong one — using it would mark the wrong messages as "mine".
    func accountIdentity(accountStore: KakaoAccountStore = KakaoAccountStore()) -> AccountIdentity? {
        if let resolved = accountStore.storedUserID(),
           KakaoAccountResolver(environment: self).resolves(userID: resolved) {
            let senderID = String(resolved)
            return AccountIdentity(senderID: senderID, fingerprint: Self.fingerprint(for: senderID))
        }

        guard let data = try? Data(contentsOf: authCacheURL),
              let cache = try? JSONDecoder().decode(AuthCache.self, from: data)
        else {
            return nil
        }

        let senderID = String(cache.userID)
        return AccountIdentity(senderID: senderID, fingerprint: Self.fingerprint(for: senderID))
    }

    func accountProfile() -> AccountProfile? {
        guard let identity = accountIdentity() else { return nil }
        return AccountProfile(label: "카카오톡", fingerprint: identity.fingerprint)
    }

    /// KakaoTalk names each signed-in account's database after that account, so
    /// more than one file means more than one account has been used on this Mac.
    /// The connector derives a single name and cannot be told which to read, so
    /// this is how TalkFlow notices it may be reading the wrong one.
    func kakaoDatabases(
        containerURL: URL = KatokEnvironment.kakaoContainerURL(),
        fileManager: FileManager = .default
    ) -> [(url: URL, modifiedAt: Date)] {
        let container = containerURL
        let urls = (try? fileManager.contentsOfDirectory(
            at: container,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls.compactMap { url in
            let name = url.lastPathComponent
            guard name.count == 78, name.allSatisfy(\.isHexDigit) else { return nil }
            guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            else {
                return nil
            }
            return (url, modified)
        }
    }

    /// Environment for every katok invocation.
    ///
    /// The connector derives the database name from a cached account id and
    /// offers no flag to choose a file, so after an account switch it reads the
    /// account that was signed out. Passing the resolved id overrides that.
    /// Nothing is passed unless the id still derives the live database, so a
    /// stale answer cannot silently point katok at the wrong account again.
    func katokProcessEnvironment(
        accountStore: KakaoAccountStore = KakaoAccountStore(),
        resolver: KakaoAccountResolver? = nil
    ) -> [String: String] {
        let resolver = resolver ?? KakaoAccountResolver(environment: self)
        guard let live = resolver.liveDatabaseName() else { return [:] }

        // The hot path is a filename comparison. Deriving a name costs a
        // 100,000-round PBKDF2, and this runs before every sync — often enough
        // that re-deriving what has not changed would dominate the sync itself.
        if let record = accountStore.stored(), record.databaseName == live {
            return ["KATOK_KAKAO_USER_ID": String(record.userID)]
        }

        // Either the file changed or the record predates name caching. Derive
        // once, and remember the answer so the next call is a comparison again.
        guard let userID = accountStore.storedUserID(),
              resolver.resolves(userID: userID)
        else {
            return [:]
        }
        try? accountStore.save(userID: userID, databaseName: live)
        return ["KATOK_KAKAO_USER_ID": String(userID)]
    }

    /// The device uuid the database name is derived from. Cached by the
    /// connector alongside the account id; unlike the account id it does not
    /// change when someone signs into a different account.
    func deviceUUID() -> String? {
        guard let data = try? Data(contentsOf: authCacheURL),
              let cache = try? JSONDecoder().decode(DeviceCache.self, from: data)
        else {
            return nil
        }
        return cache.uuid
    }

    static func kakaoContainerURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Containers/com.kakao.KakaoTalkMac/Data/Library/Application Support/com.kakao.KakaoTalkMac")
    }

    static func defaultDataDirectoryURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/katok")
    }

    private static func fingerprint(for senderID: String) -> String {
        let digest = SHA256.hash(data: Data(senderID.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "katok-\(digest)"
    }
}

/// katok writes the account identifier it recovered from KakaoTalk here so that
/// later runs do not have to redo the recovery.
private struct DeviceCache: Decodable {
    let uuid: String
}

private struct AuthCache: Decodable {
    let userID: Int

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
    }
}
