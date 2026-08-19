import Foundation
import TalkFlowApplication
import TalkFlowDomain

/// Screen-facing state for the whole app, assembled once by `TalkFlowApp`.
///
/// Views take this instead of a growing parameter list, and every screen that
/// needs the same model gets the same instance rather than its own copy.
@MainActor
public final class TalkFlowModels {
    public let responseControl: ResponseControlModel
    public let aiConnection: AIConnectionModel
    public let chatRooms: ChatRoomListModel
    public let roomSummary: RoomSummaryModel
    public let people: PeopleModel
    public let syncActivity: SyncActivityModel
    public let timeline: ActivityTimelineModel
    public let sendQueue: SendQueueModel
    public let settings: SettingsModel
    /// The 관리자 모드 section's state. Optional so a build without a database still
    /// assembles; the section is left off the settings screen then.
    public let admin: AdminRoomsModel?
    public let loadStatus: LoadConnectionStatus

    public init(
        responseControl: ResponseControlModel,
        aiConnection: AIConnectionModel,
        chatRooms: ChatRoomListModel,
        roomSummary: RoomSummaryModel,
        syncActivity: SyncActivityModel,
        timeline: ActivityTimelineModel,
        sendQueue: SendQueueModel,
        settings: SettingsModel,
        loadStatus: LoadConnectionStatus,
        admin: AdminRoomsModel? = nil,
        personNotes: (any PersonNoteStore)? = nil
    ) {
        self.responseControl = responseControl
        self.aiConnection = aiConnection
        self.chatRooms = chatRooms
        self.roomSummary = roomSummary
        // Built here rather than passed in, because the 사람 screen filters by the
        // rooms `chatRooms` has already loaded and must not read them a second
        // time: verifying the account and listing KakaoTalk's rooms is a process
        // launch, and two readings of it can disagree.
        //
        // The store is nil without a database, exactly as the burning store is.
        // Nothing can be read or written then and the screen says so, which is
        // better than an empty list that reads as nobody having been remembered.
        people = PeopleModel(roomList: chatRooms, notes: personNotes)
        self.syncActivity = syncActivity
        self.timeline = timeline
        self.sendQueue = sendQueue
        self.settings = settings
        self.admin = admin
        self.loadStatus = loadStatus
    }

    /// The shortcut that stops everything from wherever the user is, shown in
    /// the UI so it can be found before it is needed.
    public var stopShortcutName: String?

    /// Checks a changed room for an admin console command before it is drafted for,
    /// and returns whether one was consumed. Set alongside the pipeline in
    /// `startReplyPipeline`; nil in a build with no admin support, where every room
    /// is simply drafted as before.
    private var adminCommand: (@Sendable (String) async -> Bool)?

    /// Connects the sync stream to the reply pipeline. Done here rather than in
    /// an initialiser because the pipeline needs models that do not exist yet
    /// while this object is being built.
    ///
    /// `adminCommand` is threaded the same way `draftReplies` is: composition owns
    /// the use case and hands in a closure, so this file names no infrastructure.
    public func startReplyPipeline(
        _ draftReplies: DraftRepliesForChangedRooms,
        adminCommand: (@Sendable (String) async -> Bool)? = nil
    ) {
        self.adminCommand = adminCommand
        syncActivity.onSynchronized = { [weak self] report in
            guard !report.changedChatRoomIDs.isEmpty else { return }
            self?.enqueueForDrafting(report, draftReplies: draftReplies)
        }
    }

    /// Rooms drafted for as their syncs arrive — one job per room, without waiting
    /// for a batch to fill or drain.
    ///
    /// Drafting once happened inside the sync stream's own loop, which held the
    /// stream until every model call finished; a busy stretch put syncs minutes
    /// behind the messages they described. That is why rooms pile up here and the
    /// stream is read as fast as it produces. What changed since: they no longer
    /// pile up into a *batch*. A single run used to snapshot every waiting room,
    /// empty the set, and draft that whole batch — its slowest room, and the
    /// send-queue pass after it — before looking again. A room that changed while
    /// a slow room answered waited out that entire batch though the two shared
    /// nothing: an unrelated room could sit ~35s behind a room doing a web search,
    /// then all of them delivered at once.
    ///
    /// Now each room is its own job. It starts the instant its sync lands, up to
    /// `maxConcurrentRooms` at a time, and finishes on its own — a slow room holds
    /// only itself. `draftReplies` bounds generation and never touches the send
    /// queue, and `runOnce` folds overlapping passes into one, so jobs run and
    /// finish independently without delivering anything twice.
    private var draftingJobs: [String: Task<Void, Never>] = [:]
    /// Rooms whose sync landed while the concurrency ceiling was full. Held until a
    /// running job frees a slot; a set because five syncs naming one room are still
    /// one job.
    private var roomsAwaitingDrafting: Set<String> = []
    /// Rooms that changed again while their own job was still running. The job
    /// reads a snapshot from before that change, so the room is drafted once more
    /// when the job returns — rather than lost, or drafted twice at once.
    private var roomsNeedingRedraft: Set<String> = []
    /// The oldest sync instant seen per room, kept until its job takes it: the
    /// record measures how long a message went unanswered from the sync that first
    /// saw it, not whichever arrived last.
    private var detectedAtByRoom: [String: Date] = [:]
    private var synchronizedAtByRoom: [String: Date] = [:]

    private func enqueueForDrafting(
        _ report: KakaoSyncReport,
        draftReplies: DraftRepliesForChangedRooms
    ) {
        for roomID in report.changedChatRoomIDs {
            if let detected = report.detectedAt {
                detectedAtByRoom[roomID] = min(detectedAtByRoom[roomID] ?? detected, detected)
            }
            let synchronized = report.synchronizedAt
            synchronizedAtByRoom[roomID] = min(synchronizedAtByRoom[roomID] ?? synchronized, synchronized)
            beginDrafting(roomID, draftReplies: draftReplies)
        }
    }

    private func beginDrafting(_ roomID: String, draftReplies: DraftRepliesForChangedRooms) {
        // Already drafting this room: it changed again mid-flight, so ask for one
        // more pass when the running job returns rather than starting a second job
        // for the same room now.
        guard draftingJobs[roomID] == nil else {
            roomsNeedingRedraft.insert(roomID)
            return
        }
        // At the ceiling: let this room wait for a slot rather than launching an
        // eleventh Codex process. `finishDrafting` pulls it back off this set.
        guard draftingJobs.count < DraftRepliesForChangedRooms.maxConcurrentRooms else {
            roomsAwaitingDrafting.insert(roomID)
            return
        }
        roomsAwaitingDrafting.remove(roomID)
        let detectedAt = detectedAtByRoom.removeValue(forKey: roomID)
        let synchronizedAt = synchronizedAtByRoom.removeValue(forKey: roomID) ?? Date()
        draftingJobs[roomID] = Task { @MainActor [weak self] in
            // Admin console commands run first, before the global-responses switch
            // and the room-mode gate that live inside draftReplies — so a command
            // works even when responses are paused or the console is set to answer
            // nobody. A consumed command skips drafting for this room entirely.
            let consumed = await self?.adminCommand?(roomID) ?? false
            if !consumed {
                await draftReplies(
                    changedChatRoomIDs: [roomID],
                    detectedAt: detectedAt,
                    synchronizedAt: synchronizedAt
                )
            }
            // Runs the queue rather than only reloading it. A reply that waits for
            // the next poll tick reads as an answer to an old message, and in a
            // busy room the conversation has moved on. `runOnce` folds a pass that
            // lands mid-flight into one more pass, so jobs finishing together
            // deliver each row once.
            await self?.sendQueue.runOnce()
            await self?.timeline.reload()
            self?.finishDrafting(roomID, draftReplies: draftReplies)
        }
    }

    private func finishDrafting(_ roomID: String, draftReplies: DraftRepliesForChangedRooms) {
        draftingJobs[roomID] = nil
        // Changed while this job ran: draft it once more with what arrived since.
        if roomsNeedingRedraft.remove(roomID) != nil {
            beginDrafting(roomID, draftReplies: draftReplies)
        }
        // A slot just freed: start one room that was waiting on the ceiling.
        if let next = roomsAwaitingDrafting.first {
            beginDrafting(next, draftReplies: draftReplies)
        }
    }

    /// How often the quiet-room sweep actually looks, riding a loop that turns
    /// six times as often.
    ///
    /// The queue turns every ten seconds because a draft can become sendable at
    /// any instant — the user steps away, the screen unlocks. A quiet room cannot
    /// change that fast: the shortest 먼저 말 걸기 주기 is ten minutes and the room
    /// has to have been silent for thirty before that. Looking every ten seconds
    /// would ask the same question sixty times over to get the same answer, and
    /// each look re-verifies the account, which launches a process. This app is
    /// meant to sit idle for hours.
    public static let conversationOpenerSweep: TimeInterval = 60

    /// Hangs the quiet-room sweep off the send queue's poll.
    ///
    /// It cannot hang off the sync stream like everything else: that stream
    /// reports rooms that changed, and a room that has gone quiet is by
    /// definition not one of them. The queue's loop already turns for conditions
    /// nothing announces, which is the same kind of question, so it carries this
    /// rather than a second timer being started.
    public func startConversationOpener(_ openConversations: OpenConversationsInQuietRooms) {
        addPollSweep(every: Self.conversationOpenerSweep) { [weak self] in
            guard let self else { return }
            let opened = await openConversations()
            guard !opened.isEmpty else { return }
            await self.timeline.reload()
        }
    }

    /// How often the 채팅방 요약 sweep looks.
    ///
    /// Five minutes rather than the opener's one, because what it waits for moves
    /// far more slowly: a room is due after forty new messages or a day, and the
    /// busiest room measured here would take some twenty minutes to reach forty.
    /// Asking every ten seconds would re-derive the same "not yet" a hundred and
    /// twenty times, and each look re-verifies the account, which launches a
    /// process.
    public static let summaryRefreshSweep: TimeInterval = 300

    /// Hangs the summary refresh off the send queue's poll.
    ///
    /// Deliberately not off the sync stream, which is where every other reaction
    /// to a new message lives. That stream's handler runs to completion before the
    /// next sync is delivered, so a model call sitting in it would put itself in
    /// front of the next room's reply — and a reply must never wait on a refresh.
    /// This loop turns for conditions nothing announces, which is what "this room
    /// has accumulated enough to be worth re-reading" is.
    public func startSummaryRefresh(_ refreshSummaries: RefreshConversationSummaries) {
        addPollSweep(every: Self.summaryRefreshSweep) {
            await refreshSummaries()
        }
    }

    /// Work riding the queue's tick, kept as a list rather than one closure.
    ///
    /// Two things ride it now, and a second caller assigning `onPoll` would have
    /// silently replaced the first. That failure is invisible: the feature that
    /// lost its sweep simply never happens again, which is the shape of bug this
    /// app has already shipped several times.
    private var pollSweeps: [@Sendable () async -> Void] = []

    /// Adds a sweep that looks at most every `interval`, behind a throttle of its
    /// own. The interval is the only thing a sweep states: the gate itself is
    /// `PollSweepThrottle`, written once, rather than a stored instant and an `if`
    /// copied per sweep.
    private func addPollSweep(
        every interval: TimeInterval,
        _ sweep: @escaping @Sendable () async -> Void
    ) {
        let throttle = PollSweepThrottle(every: interval)
        addPollSweep {
            guard await throttle.begin() else { return }
            await sweep()
        }
    }

    private func addPollSweep(_ sweep: @escaping @Sendable () async -> Void) {
        pollSweeps.append(sweep)
        let sweeps = pollSweeps
        sendQueue.onPoll = {
            for sweep in sweeps { await sweep() }
        }
    }
}
