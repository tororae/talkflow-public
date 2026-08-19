import Foundation

/// Remembers the KakaoTalk name an account was found under, for a minute at a
/// time.
///
/// Reading it means finding a message this account sent inside an archive that
/// holds every conversation on the machine — `account_hash` narrows it but the
/// ordering still needs a temp B-tree, measured at ~10ms. The connection is asked
/// for its status before every sync and by every screen that opens, which is why
/// there is a cache at all.
///
/// It used to hold the answer for the life of the process with no way to clear it.
/// That made the one case it exists for — 「사용자가 카카오톡에서 이름을 바꿨다」 —
/// the one case it got wrong: the app went on answering to the old name until it
/// was quit and reopened, and nothing on screen said which name it was using, so
/// there was no way to find out short of reading this file.
///
/// A minute rather than a button alone. A rename should stop being wrong on its
/// own, without the user having to know a button exists; the button is for the
/// person standing in front of the screen who wants it now.
///
/// Keyed by account fingerprint: signing into another account has to resolve
/// again rather than wear the previous account's name.
final class AccountNicknameCache: @unchecked Sendable {
    /// Long enough to collapse a burst of status probes, short enough that a
    /// rename fixes itself while somebody is still wondering why it did not.
    static let lifetime: TimeInterval = 60

    private struct Entry {
        let name: String
        let readAt: Date
    }

    private let lock = NSLock()
    private var names: [String: Entry] = [:]

    /// Only an answer is remembered. katok rewrites the archive every few
    /// seconds, so a read can simply lose that race — and a brand-new account
    /// genuinely has no name yet. Caching either of those would leave the
    /// account nameless until the next expiry, long after the message that
    /// would have named it arrived.
    func nickname(
        forAccount fingerprint: String,
        now: Date = Date(),
        resolve: () -> String?
    ) -> String? {
        let fresh = lock.withLock { () -> String? in
            guard let entry = names[fingerprint],
                  now.timeIntervalSince(entry.readAt) < Self.lifetime
            else {
                return nil
            }
            return entry.name
        }
        if let fresh { return fresh }

        guard let resolved = resolve() else { return nil }
        lock.withLock { names[fingerprint] = Entry(name: resolved, readAt: now) }
        return resolved
    }

    /// Drops what is held so the next read goes back to the archive. Behind the
    /// 이름 다시 읽기 button, and used when the app is told the account changed.
    func forget() {
        lock.withLock { names.removeAll() }
    }
}
