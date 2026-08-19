import Foundation

/// Works out which KakaoTalk account is actually signed in.
///
/// KakaoTalk keeps one database per account, named after `(user_id, device
/// uuid)`. Signing into a different account creates a new file and leaves the
/// old one in place, and the connector — which derives a single name from a
/// cached id — keeps reading the account that was signed out.
///
/// So the live account is identified the other way round: find the database
/// KakaoTalk is actually writing, then find which candidate id derives that
/// name. An id that derives nothing on disk is not the signed-in account, no
/// matter which cache it came from.
struct KakaoAccountResolver: Sendable {
    struct Resolution: Equatable, Sendable {
        let userID: Int
        let databaseName: String
    }

    private let environment: KatokEnvironment
    private let deviceUUID: String?

    init(environment: KatokEnvironment = KatokEnvironment()) {
        self.environment = environment
        deviceUUID = environment.deviceUUID()
    }

    /// The database KakaoTalk has written most recently. Nothing else on disk
    /// distinguishes a live account from one that was signed out months ago.
    func liveDatabaseName() -> String? {
        environment.kakaoDatabases()
            .max { $0.modifiedAt < $1.modifiedAt }?
            .url.lastPathComponent
    }

    /// Checks a candidate against the live database rather than trusting it.
    func resolves(userID: Int) -> Bool {
        guard let deviceUUID, let live = liveDatabaseName() else { return false }
        return KakaoKeyDerivation.databaseName(userID: userID, deviceUUID: deviceUUID) == live
    }

    /// Tries every id TalkFlow knows about and returns the one that derives the
    /// live database. Deriving a name costs a PBKDF2 pass, so callers should
    /// remember the answer rather than resolving on every read.
    func resolve(candidates: [Int]) -> Resolution? {
        guard let deviceUUID, let live = liveDatabaseName() else { return nil }

        for candidate in candidates
        where KakaoKeyDerivation.databaseName(userID: candidate, deviceUUID: deviceUUID) == live {
            return Resolution(userID: candidate, databaseName: live)
        }
        return nil
    }
}
