import Foundation
import Testing
@testable import TalkFlowInfrastructure

private let databaseName = String(repeating: "a1b2", count: 19) + "cc"

@Test
func monitorWatchesTheDatabaseAndItsWriteAheadLog() {
    #expect(DatabaseFileState.isWriteVisibleDatabaseFile(databaseName))
    #expect(DatabaseFileState.isWriteVisibleDatabaseFile("\(databaseName)-wal"))
    #expect(DatabaseFileState.isWriteVisibleDatabaseFile("\(databaseName).db"))
}

/// Reading the database rewrites its shared-memory index, so a sync's own read
/// would look like new KakaoTalk activity and schedule the next sync forever.
@Test
func monitorIgnoresTheSharedMemoryIndexThatReadsTouch() {
    #expect(DatabaseFileState.isWriteVisibleDatabaseFile("\(databaseName)-shm") == false)
}

@Test
func monitorIgnoresFilesThatAreNotKakaoDatabases() {
    #expect(DatabaseFileState.isWriteVisibleDatabaseFile("Emoticon") == false)
    #expect(DatabaseFileState.isWriteVisibleDatabaseFile("com.crashlytics") == false)
    #expect(DatabaseFileState.isWriteVisibleDatabaseFile(String(repeating: "a", count: 77)) == false)
    #expect(DatabaseFileState.isWriteVisibleDatabaseFile(String(repeating: "z", count: 78)) == false)
}

@Test
func monitorReportsAppendsToTheWriteAheadLog() async throws {
    let directoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "talkflow-monitor-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directoryURL) }

    let walURL = directoryURL.appending(path: "\(databaseName)-wal")
    try Data().write(to: walURL)

    let monitor = KakaoDatabaseChangeMonitor(directoryURL: directoryURL)
    let changes = await monitor.changes(pollInterval: .milliseconds(20))

    // Appended to repeatedly rather than written once after a sleep.
    //
    // `changes` takes its baseline on its own first read and reports nothing for
    // it — 「nothing has changed relative to nothing」. A single write timed 60ms
    // out was racing that baseline: on a loaded machine the first read landed
    // *after* the write, so the baseline already held the new bytes, nothing
    // changed afterwards, and `next()` waited forever with no deadline. That is
    // this suite hanging for 20 minutes rather than failing — measured 2026-08-17,
    // three times in a full parallel run, while the test passes alone in 0.09s.
    //
    // A WAL is appended to over and over, so writing that way is also the honest
    // simulation. The size alternates between 11 and 13 bytes so each write is a
    // change the monitor can see without the file growing without bound.
    let writer = Task {
        var long = false
        while !Task.isCancelled {
            try? Data((long ? "newer message" : "new message").utf8).write(to: walURL)
            long.toggle()
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
    defer { writer.cancel() }

    let observer = Task { () -> DatabaseChangeTick? in
        for await tick in changes { return tick }
        return nil
    }
    // A deadline, so a monitor that stops noticing fails this one test instead of
    // stalling every other one behind it. Ten seconds is not a threshold anybody
    // measured — the answer arrives in under a tenth of a second when it works —
    // it is only far enough out that a busy machine is not called a failure.
    let deadline = Task {
        try? await Task.sleep(for: .seconds(10))
        observer.cancel()
    }
    defer { deadline.cancel() }

    #expect(await observer.value == .changed)
}

// MARK: - A read that never comes back

/// Stands in for the thing that cannot be written as a test any other way.
///
/// macOS refuses to enumerate another app's container by not answering, so the
/// read has to be held open on purpose and released when the test is done with
/// it — a real sleep would leave the thread parked long after the assertion.
private final class Gate: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var entries = 0

    var timesEntered: Int {
        lock.withLock { entries }
    }

    /// Waits until the read has actually begun, or gives up.
    ///
    /// `startRead` stamps its clock on the actor and hands the read to a global
    /// queue, so the poll reports `.stalled` on time whether or not GCD has run
    /// the block yet. Asserting the entry count without waiting for it asserts
    /// that GCD was prompt — measured 2026-08-19 under a loaded parallel suite,
    /// it is not, and the count read 0. Returns false on giving up so the caller
    /// fails rather than passing on an unstarted read.
    func waitForFirstEntry() -> Bool {
        let deadline = ContinuousClock().now + .seconds(2)
        while ContinuousClock().now < deadline {
            if timesEntered > 0 { return true }
            usleep(1_000)
        }
        return false
    }

    func enterAndWait() {
        lock.withLock { entries += 1 }
        semaphore.wait()
    }

    func open() {
        semaphore.signal()
    }
}

/// The first `count` ticks, or nil if they do not arrive.
///
/// `next()` on its own has no deadline, so a monitor that stopped reporting would
/// stall this file and every test queued behind it instead of failing — which is
/// how this suite came to hang for twenty minutes rather than go red. Ten seconds
/// is not a measured threshold; these ticks arrive in tens of milliseconds, and it
/// is only far enough out that a loaded machine is not called a failure.
private func firstTicks(
    _ count: Int,
    of changes: AsyncStream<DatabaseChangeTick>
) async -> [DatabaseChangeTick]? {
    let observer = Task { () -> [DatabaseChangeTick] in
        var seen: [DatabaseChangeTick] = []
        for await tick in changes {
            seen.append(tick)
            if seen.count == count { break }
        }
        return seen
    }
    let deadline = Task {
        try? await Task.sleep(for: .seconds(10))
        observer.cancel()
    }
    defer { deadline.cancel() }

    let seen = await observer.value
    return seen.count == count ? seen : nil
}

/// The whole point. A read that hangs used to be indistinguishable from a quiet
/// chat: `snapshot()` returned an empty array, the comparison found no change,
/// and detection reported itself healthy while it was deaf. Twice in one evening
/// the app sat like that for minutes with a green light on screen.
@Test
func aReadThatNeverComesBackIsReportedInsteadOfLookingLikeAQuietChat() async {
    let gate = Gate()
    let monitor = KakaoDatabaseChangeMonitor(deadline: .milliseconds(40)) {
        gate.enterAndWait()
        return []
    }
    defer { gate.open() }

    let changes = await monitor.changes(pollInterval: .milliseconds(10))

    #expect(await firstTicks(1, of: changes) == [.stalled])
}

/// A blocked read cannot be cancelled — the thread stays in the syscall — so a
/// poll that started a new one each second would abandon sixty threads a minute
/// and end in a process with none left. One is the price of noticing; a second
/// is a leak.
@Test
func aStalledReadIsNeverStartedTwice() async {
    let gate = Gate()
    let monitor = KakaoDatabaseChangeMonitor(deadline: .milliseconds(20)) {
        gate.enterAndWait()
        return []
    }
    defer { gate.open() }

    let changes = await monitor.changes(pollInterval: .milliseconds(10))
    #expect(await firstTicks(4, of: changes) == [.stalled, .stalled, .stalled, .stalled])

    #expect(gate.waitForFirstEntry())
    // Exactly one, never a second: a blocked read cannot be cancelled, so a
    // second start is a thread abandoned for good.
    #expect(gate.timesEntered == 1)
}
