import Foundation
import TalkFlowDomain

/// Converts local KakaoTalk database changes into completed katok sync reports.
/// It intentionally performs no AI call and no message send; those policies live
/// above this infrastructure boundary.
public actor KatokRealtimeSyncService: KakaoSyncSource {
    /// A sync re-reads KakaoTalk's database in full, so an active conversation
    /// would otherwise keep a core busy continuously. Waiting out this interval
    /// bounds that cost.
    ///
    /// Five seconds, when this was written, because a sync was measured at ~2.9s
    /// and the interval had to be worth the pause. Re-measured 2026-08-10 on the
    /// same machine: **0.70s warm**, 4.4s on a cold cache. The premise moved by a
    /// factor of four and the delay it justified was being charged to every reply
    /// — it is the first thing that happens after somebody speaks.
    public static let defaultMinimumInterval: Duration = .seconds(2)

    /// Names the one cause worth naming. Every other way the read could hang is
    /// rarer than this one and has the same remedy anyway — look at the screen
    /// the dialog went to, or register the app so it stops being asked.
    static let stallReason = "카카오톡 데이터를 읽지 못하고 있습니다. 권한 요청 창이 다른 화면에 떠 있는지 확인하세요."

    private let monitor: KakaoDatabaseChangeMonitor
    private let syncRunner: KatokSyncRunner
    private let minimumInterval: Duration

    public init?(
        monitor: KakaoDatabaseChangeMonitor = KakaoDatabaseChangeMonitor(),
        minimumInterval: Duration = KatokRealtimeSyncService.defaultMinimumInterval
    ) {
        guard let syncRunner = KatokSyncRunner() else { return nil }
        self.monitor = monitor
        self.syncRunner = syncRunner
        self.minimumInterval = minimumInterval
    }

    public func events() async -> AsyncStream<KakaoSyncEvent> {
        let changes = await monitor.changes()
        let syncRunner = syncRunner
        let minimumInterval = minimumInterval

        return AsyncStream { continuation in
            let task = Task {
                let clock = ContinuousClock()
                var lastSyncFinishedAt: ContinuousClock.Instant?

                for await tick in changes {
                    guard !Task.isCancelled else { break }

                    // A stall says nothing about the archive, so it must not
                    // pay the sync interval or reset it — it is reported and
                    // the next poll is waited for like any other.
                    if tick == .stalled {
                        continuation.yield(.stalled(reason: Self.stallReason))
                        continue
                    }

                    // Stamped before the interval is waited out, not after: the
                    // wait is part of how long the message went unnoticed, and it
                    // is the largest slice of that. A report that started its
                    // clock after the sleep would put its own worst delay outside
                    // the record.
                    let detectedAt = Date()

                    if let lastSyncFinishedAt {
                        let elapsed = clock.now - lastSyncFinishedAt
                        if elapsed < minimumInterval {
                            try? await Task.sleep(for: minimumInterval - elapsed)
                        }
                    }
                    guard !Task.isCancelled else { break }

                    do {
                        continuation.yield(.synchronized(try await syncRunner.sync(detectedAt: detectedAt)))
                    } catch {
                        continuation.yield(.failed(reason: error.localizedDescription))
                    }
                    lastSyncFinishedAt = clock.now
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
