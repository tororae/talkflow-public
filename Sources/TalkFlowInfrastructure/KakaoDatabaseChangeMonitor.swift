import Foundation

/// What one poll of KakaoTalk's database directory found.
///
/// A stall is its own answer rather than an absence of one. Reading the
/// directory and finding nothing new looks identical, from the outside, to not
/// being able to read it at all — and the second one means the app has stopped
/// working while the first means the chat is quiet.
public enum DatabaseChangeTick: Equatable, Sendable {
    case changed
    /// The read did not come back. Repeats every poll until it does.
    case stalled
}

/// Polls only KakaoTalk's local database directory. A short polling interval is
/// deliberate here: it works without UI automation and catches WAL updates even
/// when KakaoTalk keeps the main database file open.
public actor KakaoDatabaseChangeMonitor {
    /// Reading the directory. Stored as a closure so a read that never comes
    /// back can be tested without needing one that never comes back.
    private let listDirectory: @Sendable () -> [DatabaseFileState]
    private let deadline: Duration

    private let clock = ContinuousClock()
    /// Non-nil while a read is out. Cleared by the read itself, whenever it
    /// comes back — which may be never.
    private var readStartedAt: ContinuousClock.Instant?
    private var newest: [DatabaseFileState]?
    private var newestIsUnread = false

    public init() {
        self.init(directoryURL: Self.defaultDirectoryURL())
    }

    public init(
        directoryURL: URL,
        deadline: Duration = KakaoDatabaseChangeMonitor.defaultDeadline
    ) {
        self.init(
            deadline: deadline,
            listDirectory: { Self.contents(of: directoryURL) }
        )
    }

    init(
        deadline: Duration = KakaoDatabaseChangeMonitor.defaultDeadline,
        listDirectory: @escaping @Sendable () -> [DatabaseFileState]
    ) {
        self.deadline = deadline
        self.listDirectory = listDirectory
    }

    /// Generous next to a one-second poll, because the cost of being wrong is
    /// asymmetric: a slow disk answering late is a false alarm on screen, and a
    /// real block never answers at all, so no threshold misses it.
    public static let defaultDeadline: Duration = .seconds(5)

    public func changes(pollInterval: Duration = .seconds(1)) -> AsyncStream<DatabaseChangeTick> {
        // A sync takes seconds while polling takes one, so bursts of writes must
        // collapse into a single pending run rather than queueing a sync each.
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                var previous: [DatabaseFileState]?
                while !Task.isCancelled {
                    switch await poll() {
                    case let .files(current):
                        // The first read sets the baseline without reporting
                        // it: nothing has changed relative to nothing.
                        if let previous, current != previous {
                            continuation.yield(.changed)
                        }
                        previous = current
                    case .stalled:
                        continuation.yield(.stalled)
                    case .waiting:
                        break
                    }

                    try? await Task.sleep(for: pollInterval)
                    guard !Task.isCancelled else { break }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    enum Reading: Equatable {
        case files([DatabaseFileState])
        /// A read has been out longer than the deadline.
        case stalled
        /// A read is out and still within its deadline. Says nothing either way.
        case waiting
    }

    /// Starts a read if none is out, and answers with what is known right now.
    ///
    /// It never waits for the read, and that is the whole design. macOS refuses
    /// to enumerate another app's container by not answering: no `EPERM`, no
    /// error, no cancellation. The thread stays in the syscall until consent
    /// arrives, and consent can wait forever because the dialog appears wherever
    /// the frontmost app is — regularly not the screen anybody is looking at.
    /// Twice in one evening that left the app running, green, and blind.
    ///
    /// A poll that waited on such a read would be exactly as stuck as the read,
    /// which is how the first attempt at this fix hung the test suite. So the
    /// deadline is only ever consulted, never awaited.
    ///
    /// And a second read is never started. Abandoning one thread is the price of
    /// noticing; abandoning one per second is a leak that ends in a process with
    /// no threads left.
    func poll() -> Reading {
        if readStartedAt == nil { startRead() }

        if newestIsUnread {
            newestIsUnread = false
            return .files(newest ?? [])
        }
        if let readStartedAt, clock.now - readStartedAt > deadline {
            return .stalled
        }
        return .waiting
    }

    /// GCD rather than a `Task`: Swift's cooperative pool holds one thread per
    /// core, so parking one there stops every other async thing the app is doing
    /// — the opposite of what this exists for. A global queue grows instead, and
    /// a stuck thread on it costs only itself.
    private func startRead() {
        readStartedAt = clock.now
        let listDirectory = listDirectory
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let files = listDirectory()
            Task { await self?.finishRead(files) }
        }
    }

    private func finishRead(_ files: [DatabaseFileState]) {
        newest = files
        newestIsUnread = true
        readStartedAt = nil
    }

    static func defaultDirectoryURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Containers/com.kakao.KakaoTalkMac/Data/Library/Application Support/com.kakao.KakaoTalkMac")
    }

    /// Makes its own `FileManager` because the read now happens off this actor
    /// and `FileManager` is not `Sendable`. Instances are cheap and nothing here
    /// depends on state carried on one — which is also why the injection point
    /// moved to the whole read: a fake file manager could never have simulated
    /// the failure that matters, a call that does not return.
    private static func contents(of directoryURL: URL) -> [DatabaseFileState] {
        let urls = (try? FileManager().contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls.compactMap(DatabaseFileState.init).sorted { $0.path < $1.path }
    }
}

struct DatabaseFileState: Equatable, Sendable {
    let path: String
    let modificationDate: Date
    let fileSize: Int

    init?(_ url: URL) {
        guard Self.isWriteVisibleDatabaseFile(url.lastPathComponent) else { return nil }

        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        guard let modificationDate = values?.contentModificationDate,
              let fileSize = values?.fileSize
        else { return nil }

        path = url.path
        self.modificationDate = modificationDate
        self.fileSize = fileSize
    }

    /// Only files a *writer* touches count as a change.
    ///
    /// SQLite rewrites the `-shm` index whenever anyone opens the database, so a
    /// sync's own read would look like new KakaoTalk activity and trigger the
    /// next sync forever. The main database and `-wal` move only on writes.
    static func isWriteVisibleDatabaseFile(_ name: String) -> Bool {
        if name.hasSuffix("-shm") { return false }

        let baseName = name
            .replacingOccurrences(of: "-wal", with: "")
            .replacingOccurrences(of: ".db", with: "")
        guard baseName.count == 78 else { return false }
        return baseName.allSatisfy { $0.isHexDigit }
    }
}
