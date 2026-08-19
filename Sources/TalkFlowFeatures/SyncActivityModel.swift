import Foundation
import Observation
import TalkFlowApplication
import TalkFlowDomain

@MainActor
@Observable
public final class SyncActivityModel {
    public private(set) var isObserving = false
    public private(set) var lastSyncedAt: Date?
    public private(set) var lastReport: KakaoSyncReport?
    public private(set) var lastFailure: String?
    /// Set while detection is running but not answering.
    ///
    /// Its own field rather than a `lastFailure` string because the two need
    /// opposite treatment on screen. A failed sync is history — it happened, it
    /// is over, and the next one may work. A stall is the present tense: it is
    /// still happening, nothing will arrive until somebody acts, and showing it
    /// beside a green 감지 중 is how an app sits blind for hours looking healthy.
    public private(set) var stallReason: String?
    /// New messages archived since the app launched, not since the last sync.
    public private(set) var newMessagesThisSession = 0
    public private(set) var recentlyChangedRoomIDs: [String] = []

    /// Running, but not hearing anything.
    public var isStalled: Bool { stallReason != nil }

    /// Runs after each successful sync. Set by the composition root once the
    /// models that the reply pipeline needs all exist.
    public var onSynchronized: (@MainActor (KakaoSyncReport) async -> Void)?

    private let observeSync: ObserveKakaoSync?
    private var observation: Task<Void, Never>?

    public init(observeSync: ObserveKakaoSync?) {
        self.observeSync = observeSync
    }

    public var statusText: String {
        guard observeSync != nil else {
            return "katok을 찾지 못해 대화 감지를 시작할 수 없습니다."
        }
        // Ahead of everything else it could say. While this is set, the counts
        // and the last-synced time are all describing a moment that has stopped
        // moving, and reading them as current is the mistake being fixed.
        if let stallReason {
            return stallReason
        }
        if let lastFailure {
            return lastFailure
        }
        guard let lastSyncedAt else {
            return isObserving ? "새 메시지를 기다리는 중입니다." : "대화 감지가 꺼져 있습니다."
        }
        return "마지막 반영 \(Self.timeFormatter.string(from: lastSyncedAt)) · 이번 세션 새 메시지 \(newMessagesThisSession)건"
    }

    public func startObserving() {
        guard observation == nil, let observeSync else { return }
        isObserving = true
        observation = Task { [weak self] in
            for await event in await observeSync() {
                guard !Task.isCancelled else { break }
                self?.apply(event)

                if case let .synchronized(report) = event, let handler = self?.onSynchronized {
                    await handler(report)
                }
            }
            self?.isObserving = false
        }
    }

    public func stopObserving() {
        observation?.cancel()
        observation = nil
        isObserving = false
    }

    private func apply(_ event: KakaoSyncEvent) {
        switch event {
        case let .synchronized(report):
            lastFailure = nil
            // A sync that ran is proof the read came back, whatever it found.
            stallReason = nil
            lastSyncedAt = Date()
            lastReport = report
            newMessagesThisSession += report.insertedMessages
            if !report.changedChatRoomIDs.isEmpty {
                recentlyChangedRoomIDs = report.changedChatRoomIDs
            }
        case let .failed(reason):
            lastFailure = reason
        case let .stalled(reason):
            stallReason = reason
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
