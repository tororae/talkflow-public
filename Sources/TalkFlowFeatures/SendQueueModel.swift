import Foundation
import Observation
import TalkFlowApplication
import TalkFlowDomain

@MainActor
@Observable
public final class SendQueueModel {
    /// The queue waits on conditions that change with nothing to observe — the
    /// user stepping away, the screen unlocking — so it is polled rather than
    /// driven by events. Delivery of a fresh draft does not wait for a tick:
    /// the reply pipeline runs the queue as soon as it enqueues one.
    public static let pollInterval: Duration = .seconds(10)

    public private(set) var waiting: [PendingSend] = []
    public private(set) var recent: [PendingSend] = []
    public private(set) var isRunning = false

    /// Work that has to happen on a clock rather than on an event, riding this
    /// loop rather than starting a second one.
    ///
    /// 먼저 말 걸기 is the only thing here so far, and it is here because a room
    /// that has gone quiet reports no changes — the sync-driven pipeline will
    /// never look at it again, which is precisely the case that feature exists
    /// for. A timer of its own would be a second reason for the Mac to stay
    /// awake ([7.3](DESIGN.md)) doing the same shape of work this one already
    /// wakes for.
    ///
    /// On the tick only, never on the kick the reply pipeline gives this model
    /// after it queues a draft. That kick means a room just spoke, which is the
    /// opposite of the condition being looked for. How often the work behind this
    /// actually does anything is its own business — the queue's ten seconds are
    /// for drafts, not for whatever else rides along.
    public var onPoll: (@Sendable () async -> Void)?

    let processQueue: ProcessSendQueue
    private let sendStore: any PendingSendStore
    private var loop: Task<Void, Never>?
    private var isProcessing = false
    private var wantsAnotherPass = false

    public init(processQueue: ProcessSendQueue, sendStore: any PendingSendStore) {
        self.processQueue = processQueue
        self.sendStore = sendStore
    }

    public var summary: String {
        if !waiting.isEmpty {
            return "전송 대기 \(waiting.count)건"
        }
        let sent = recent.filter { $0.state == .sent }.count
        return sent > 0 ? "대기 중인 전송 없음 · 지금까지 \(sent)건 전송" : "대기 중인 전송이 없습니다."
    }

    public func start() {
        guard loop == nil else { return }
        isRunning = true
        loop = Task { [weak self] in
            // Before the first pass, and only ever here. Anything still queued
            // belongs to a run that has ended, and delivering it now is a burst
            // of answers to messages nobody is still looking at.
            await self?.processQueue.discardDraftsLeftByPreviousRun()
            await self?.refresh()

            while !Task.isCancelled {
                // The queue first. The sweeps riding this loop can make model
                // calls of their own — 먼저 말 걸기 and 채팅방 요약 both do, once
                // per room — and a draft waiting to go out used to queue behind
                // however many of those a tick happened to fire. A reply that a
                // person is waiting on does not wait on a note about the room.
                //
                // What this costs is that anything a sweep enqueues waits for the
                // next tick, ten seconds away. Nobody is waiting on those: a room
                // that has been quiet for half an hour is not counting seconds.
                await self?.runOnce()
                await self?.onPoll?()
                try? await Task.sleep(for: SendQueueModel.pollInterval)
            }
            self?.isRunning = false
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
        isRunning = false
    }

    /// Only one pass runs at a time. The poll loop and the pipeline's kick can
    /// arrive together, and two passes would read the same queued rows and
    /// deliver each of them twice. A kick that lands mid-pass asks for one more
    /// pass rather than being dropped, so a draft enqueued a moment ago still
    /// goes out without waiting for the next tick.
    public func runOnce() async {
        guard !isProcessing else {
            wantsAnotherPass = true
            return
        }
        isProcessing = true
        defer { isProcessing = false }

        repeat {
            wantsAnotherPass = false
            await processQueue()
            await refresh()
        } while wantsAnotherPass
    }

    public func refresh() async {
        waiting = (try? await sendStore.waiting()) ?? []
        recent = (try? await sendStore.recent(limit: 50)) ?? []
    }
}
