import Foundation
import TalkFlowDomain

/// Walks the send queue and delivers only what still passes every check.
///
/// Runs on a timer rather than reacting to the draft that created the entry:
/// most of the conditions it waits on — the user stepping away, the screen
/// unlocking, the settling delay elapsing — change on their own, with no event
/// to hang a callback on.
public struct ProcessSendQueue: Sendable {
    private let connection: any KakaoConnection
    private let policyStore: any RoomPolicyStore
    private let settingsStore: any AppSettingsStore
    private let sendStore: any PendingSendStore
    private let actionLog: any AgentActionLog
    private let sender: any MessageSender
    private let activityMonitor: any SystemActivityMonitor
    private let displayWaker: (any DisplayWaker)?
    private let gate: SendGate

    public init(
        connection: any KakaoConnection,
        policyStore: any RoomPolicyStore,
        settingsStore: any AppSettingsStore,
        sendStore: any PendingSendStore,
        actionLog: any AgentActionLog,
        sender: any MessageSender,
        activityMonitor: any SystemActivityMonitor,
        displayWaker: (any DisplayWaker)? = nil,
        gate: SendGate = SendGate()
    ) {
        self.connection = connection
        self.policyStore = policyStore
        self.settingsStore = settingsStore
        self.sendStore = sendStore
        self.actionLog = actionLog
        self.sender = sender
        self.activityMonitor = activityMonitor
        self.displayWaker = displayWaker
        self.gate = gate
    }

    /// Drops every draft that was still waiting when the app last stopped.
    ///
    /// Run once at launch, before the queue turns. A draft outlives a restart
    /// only by having been unable to go out, and the app was then not running
    /// for however long it took to come back — so the queue's first act used to
    /// be a burst of replies to messages nobody was still looking at. Observed:
    /// four drafts, nine minutes old, delivered eight seconds apart.
    ///
    /// Dropping is the safe direction. A reply not sent can be sent again by a
    /// person from the timeline, or simply not missed; a reply sent nine minutes
    /// into a conversation that moved on cannot be taken back.
    ///
    /// Recorded rather than deleted quietly, because a room that was expecting an
    /// answer and did not get one is exactly the silence the timeline exists to
    /// explain.
    public func discardDraftsLeftByPreviousRun() async {
        guard let waiting = try? await sendStore.waiting(), !waiting.isEmpty else { return }
        for send in waiting {
            _ = await resolve(
                send,
                state: .cancelled,
                detail: "앱이 다시 시작되어 보내지 않았습니다. 대화가 이어졌을 수 있습니다.",
                timeline: ActionTimeline()
                    .stamping(.queued, at: send.createdAt, note: send.detail.isEmpty ? nil : send.detail)
                    .stamping(.cancelled)
            )
        }
    }

    @discardableResult
    public func callAsFunction(now: Date = Date()) async -> [PendingSend] {
        // A pass delivers its entries one after another and each takes seconds,
        // so `now` stops being now almost immediately. Stamping the record with
        // it made two drafts delivered twenty-five seconds apart claim the same
        // 채팅창 입력 시작, which reads as the queue starting both at once and
        // hides the wait the second one actually served.
        //
        // Real elapsed time is laid on top of `now` rather than read off the
        // clock directly, so a test that passes a fixed instant still gets a
        // timeline that is internally consistent.
        let passStartedAt = Date()
        func instant() -> Date { now.addingTimeInterval(Date().timeIntervalSince(passStartedAt)) }

        guard let queued = try? await sendStore.waiting(), !queued.isEmpty else { return [] }

        let fingerprint: String?
        if case let .connected(account) = await connection.status() {
            fingerprint = account.fingerprint
        } else {
            fingerprint = nil
        }

        let globalEnabled = (try? await settingsStore.globalResponsesEnabled()) ?? false
        let usePolicyAccepted = (try? await settingsStore.sendUsePolicyAccepted()) ?? false
        let mayWakeDisplay = (try? await settingsStore.wakesDisplayToSend()) ?? false
        var activity = activityMonitor.snapshot()

        // "Which rooms are there" and "could the room list be read" are different
        // questions, and answering the first with a failure of the second is how
        // a reply the user is waiting on gets cancelled and never comes back.
        // The archive is rewritten every few seconds, so a read landing mid-write
        // is ordinary; the queue simply waits for the next pass.
        guard let rooms = try? await connection.chatRooms(), !rooms.isEmpty else { return [] }

        // A locked screen owns the front, so UI automation has nothing to type
        // into. Waking gives it a target; if macOS has started asking for a
        // password the screen stays locked and every draft simply keeps waiting.
        if activity.screenLocked, mayWakeDisplay, usePolicyAccepted, globalEnabled,
           let displayWaker, await hasSendableWork(queued, rooms: rooms) {
            await displayWaker.wake()
            activity = activityMonitor.snapshot()
        }

        var resolved: [PendingSend] = []
        for send in queued {
            let outcome = await process(
                send,
                rooms: rooms,
                fingerprint: fingerprint,
                globalEnabled: globalEnabled,
                usePolicyAccepted: usePolicyAccepted,
                activity: activity,
                now: now,
                instant: instant
            )
            if let outcome { resolved.append(outcome) }
        }
        return resolved
    }

    /// Waking is a visible side effect, so it only happens when at least one
    /// queued draft would actually go out once the screen is available.
    private func hasSendableWork(_ queued: [PendingSend], rooms: [ChatRoom]) async -> Bool {
        for send in queued {
            guard let room = rooms.first(where: { $0.id == send.chatRoomID }),
                  let policy = try? await policyStore.policy(
                      for: room,
                      accountFingerprint: send.accountFingerprint
                  )
            else {
                continue
            }
            if policy.deliveryMode.deliversAutomatically, send.eligibleAt <= Date() {
                return true
            }
        }
        return false
    }

    private func process(
        _ send: PendingSend,
        rooms: [ChatRoom],
        fingerprint: String?,
        globalEnabled: Bool,
        usePolicyAccepted: Bool,
        activity: SystemActivitySnapshot,
        now: Date,
        instant: () -> Date
    ) async -> PendingSend? {
        guard let room = rooms.first(where: { $0.id == send.chatRoomID }) else {
            return await resolve(send, state: .cancelled, detail: "채팅방을 더 이상 찾을 수 없습니다.")
        }
        guard let policy = try? await policyStore.policy(
            for: room,
            accountFingerprint: send.accountFingerprint
        ) else {
            return await resolve(send, state: .cancelled, detail: "채팅방 정책을 확인하지 못했습니다.")
        }

        let latest = try? await connection.recentMessages(in: room, limit: 1).last
        let verdict = gate.evaluate(
            SendGateRequest(
                send: send,
                policy: policy,
                globalResponsesEnabled: globalEnabled,
                usePolicyAccepted: usePolicyAccepted,
                currentAccountFingerprint: fingerprint,
                latestMessageID: latest?.id,
                latestMessageSenderID: latest.flatMap { $0.isFromMe ? nil : $0.sender.id },
                activity: activity,
                now: now
            )
        )

        switch verdict {
        case let .wait(reason):
            // Written down rather than simply returned. A draft that is patiently
            // waiting and one that is stuck look identical from outside the
            // queue, and that is precisely the question when nothing arrives —
            // an earlier investigation searched `pending_sends` for '사용 중' and
            // '안정화', found nothing, and could not tell whether that meant the
            // waits never happened or merely that nobody had recorded them.
            //
            // Only when the reason changes: the queue comes back every ten
            // seconds and rewriting the same sentence sixty times would be a
            // write per tick for a fact that has not moved.
            if send.detail != reason.explanation {
                try? await sendStore.resolve(id: send.id, state: .waiting, detail: reason.explanation)
            }
            return nil
        case let .cancel(reason):
            // Timed like a delivery, because the interesting number is the same
            // one: how long the draft sat. A quarter of this queue's drafts are
            // dropped as 대화가 이어져, and how long they lived before that is the
            // measurement of whether generation is keeping up with the room.
            return await resolve(
                send,
                state: .cancelled,
                detail: Self.cancelDetail(reason, lastAttempt: send.detail),
                room: room,
                timeline: ActionTimeline()
                    .stamping(.queued, at: send.createdAt)
                    .stamping(.cancelled, at: instant(), note: reason.explanation)
            )
        case .send:
            return await deliver(send, room: room, instant: instant)
        }
    }

    private func deliver(_ send: PendingSend, room: ChatRoom, instant: () -> Date) async -> PendingSend? {
        // The queue entry's own creation time, not now: this stage happened when
        // the draft was written, and the gap after it is the wait being measured.
        // The last reason the gate gave rides along, because by the time a draft
        // is finally let out the reason it was held is the only thing that
        // explains the gap.
        var timeline = ActionTimeline()
            .stamping(.queued, at: send.createdAt, note: send.detail.isEmpty ? nil : send.detail)
            .stamping(.sendAttempted, at: instant())

        do {
            let receipt = try await sender.send(
                text: send.text,
                toChatRoomID: send.chatRoomID,
                named: room.displayName,
                // Nobody asked for this right now, so every rule about not
                // interrupting the person at the keyboard still applies.
                origin: .automatic
            )
            // The route is on the stage whose length it explains. A send that
            // took twenty seconds and one that took one look identical without
            // it, and the difference is which of the two ways in was available.
            timeline.stamp(.sent, at: instant(), note: receipt.explanation)
            return await resolve(send, state: .sent, detail: "전송했습니다.", room: room, timeline: timeline)
        } catch let failure as MessageSendFailure where failure.isRetryable {
            // Nothing was delivered and a later attempt can succeed, so the draft
            // stays queued. The gate's age limit stops it retrying forever.
            //
            // The reason is written onto the entry rather than dropped. A draft
            // that keeps failing looks exactly like one that is patiently waiting
            // its turn, and the difference is the whole question when nothing is
            // arriving. It replaces the previous reason instead of accumulating,
            // so a retry every few seconds does not bury the timeline.
            let detail = Self.retryDetail(for: failure)
            try? await sendStore.resolve(id: send.id, state: .waiting, detail: detail)

            // A failure that retrying cannot clear is put where a person looks.
            // Left in the queue's own column it is invisible: the draft ages out
            // after fifteen minutes of silent retries and the user never learns
            // that the room's window simply had to be open. Recorded once per
            // reason, because the queue comes back every few seconds and a row
            // per attempt would bury the timeline it is meant to explain.
            if failure.needsUserAction, send.detail != detail {
                try? await actionLog.record(
                    AgentAction(
                        accountFingerprint: send.accountFingerprint,
                        chatRoomID: send.chatRoomID,
                        chatRoomName: room.displayName,
                        kind: .failed,
                        triggerMessageID: send.triggerMessageID,
                        detail: detail,
                        timeline: timeline.stamping(.failed, at: instant(), note: failure.message)
                    )
                )
            }
            return nil
        } catch {
            return await resolve(
                send,
                state: .failed,
                detail: error.localizedDescription,
                room: room,
                timeline: timeline.stamping(.failed, at: instant(), note: error.localizedDescription)
            )
        }
    }

    /// A draft that ages out takes its last attempt's reason with it.
    ///
    /// 「초안이 오래되어 취소했습니다」 alone says a draft died of old age and not
    /// a word about what it spent that age failing at — and the retry reasons are
    /// otherwise invisible, because a retryable failure writes to the queue entry
    /// and the entry is overwritten by whatever happens next.
    static func cancelDetail(_ reason: SendBlockReason, lastAttempt: String) -> String {
        guard reason == .tooOld, !lastAttempt.isEmpty else { return reason.explanation }
        return "\(reason.explanation) 마지막 시도: \(lastAttempt)"
    }

    /// "재시도 중" is the right thing to say about a screen state that passes on
    /// its own. It is the wrong thing to say when the retry cannot work until
    /// somebody opens a window, so that case leads with what to do instead.
    private static func retryDetail(for failure: MessageSendFailure) -> String {
        failure.needsUserAction ? failure.explanation : "재시도 중입니다. \(failure.message)"
    }

    /// Every outcome is written to the queue and mirrored into the timeline, so
    /// a cancelled draft is as visible as a delivered one.
    private func resolve(
        _ send: PendingSend,
        state: PendingSend.State,
        detail: String,
        room: ChatRoom? = nil,
        timeline: ActionTimeline = ActionTimeline()
    ) async -> PendingSend {
        try? await sendStore.resolve(id: send.id, state: state, detail: detail)

        if state != .cancelled || !detail.isEmpty {
            try? await actionLog.record(
                AgentAction(
                    accountFingerprint: send.accountFingerprint,
                    chatRoomID: send.chatRoomID,
                    chatRoomName: room?.displayName ?? send.chatRoomName,
                    kind: state == .sent ? .sent : (state == .failed ? .failed : .held),
                    triggerMessageID: send.triggerMessageID,
                    replyText: state == .sent ? send.text : nil,
                    detail: detail,
                    timeline: timeline
                )
            )
        }

        var updated = send
        updated.state = state
        updated.detail = detail
        return updated
    }
}
