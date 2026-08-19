import TalkFlowApplication
import TalkFlowDomain
import TalkFlowFeatures
import TalkFlowInfrastructure

/// The one place concrete adapters are chosen. Everything else names protocols.
enum TalkFlowComposition {
    /// Opened once and shared. A second connection to the same file would let a
    /// stale read undo a fresh write.
    private static let database: TalkFlowDatabase? = try? TalkFlowDatabase()
    private nonisolated(unsafe) static var stopHotKey: GlobalStopHotKey?

    @MainActor
    static func makeModels() -> TalkFlowModels {
        let kakao = KatokConnection()
        let policyStore = policyStore()
        let settingsStore = settingsStore()
        let actionLog = actionLog()
        let sendStore = sendStore()
        let summaryStore = summaryStore()
        let burningStore = burningStore()
        let personNotes = personNotes()
        let adminStore = adminRoomStore()
        let settings = ManageAppSettings(store: settingsStore)
        let sender = messageSender(settingsStore: settingsStore)
        let model = aiModel(settingsStore: settingsStore)

        let models = TalkFlowModels(
            responseControl: ResponseControlModel(
                settings: settings,
                wakefulness: MacWakefulnessController()
            ),
            aiConnection: AIConnectionModel(connection: CodexCLIConnection()),
            chatRooms: ChatRoomListModel(
                loadRooms: LoadRoomsWithPolicies(
                    connection: kakao,
                    policyStore: policyStore,
                    settingsStore: settingsStore
                ),
                saveRoomPolicy: SaveRoomPolicy(policyStore: policyStore),
                readRoomPolicy: ReadRoomPolicy(policyStore: policyStore),
                hideRoom: HideChatRoom(policyStore: policyStore),
                inspectCalls: InspectRecentCalls(connection: kakao),
                inspectPresence: InspectRoomPresence(connection: kakao),
                inspectCycle: InspectJudgementCycle(actionLog: actionLog)
            ),
            roomSummary: RoomSummaryModel(
                manage: ManageConversationSummary(
                    connection: kakao,
                    summaryStore: summaryStore,
                    writer: CodexSummaryWriter(model: model),
                    personNotes: personNotes,
                    policyStore: policyStore,
                    actionLog: actionLog
                )
            ),
            syncActivity: SyncActivityModel(
                observeSync: KatokRealtimeSyncService().map(ObserveKakaoSync.init(source:))
            ),
            timeline: ActivityTimelineModel(
                log: actionLog,
                reviewDrafts: ReviewDrafts(
                    actionLog: actionLog,
                    settingsStore: settingsStore,
                    connection: kakao,
                    sender: sender,
                    // So 무시 and 보내기 reach the queue's copy of the draft too.
                    // Without this the queue delivered a draft the user had
                    // already dismissed.
                    sendStore: sendStore
                )
            ),
            sendQueue: SendQueueModel(
                processQueue: ProcessSendQueue(
                    connection: kakao,
                    policyStore: policyStore,
                    settingsStore: settingsStore,
                    sendStore: sendStore,
                    actionLog: actionLog,
                    sender: sender,
                    activityMonitor: MacSystemActivityMonitor(),
                    displayWaker: MacDisplayWaker()
                ),
                sendStore: sendStore
            ),
            settings: SettingsModel(settings: settings),
            loadStatus: LoadConnectionStatus(connection: kakao),
            // The only place admin mode is switched. The store is nil without a
            // database, and the section degrades exactly as the others do.
            admin: AdminRoomsModel(connection: kakao, store: adminStore),
            personNotes: personNotes
        )

        // Registered against the assembled models so the stop reaches the same
        // state the UI switches, and kept alive for the app's lifetime.
        let stopHotKey = GlobalStopHotKey { [weak models] in
            Task { @MainActor in models?.responseControl.stopEverything() }
        }
        if stopHotKey.register() {
            models.stopShortcutName = GlobalStopHotKey.displayName
            Self.stopHotKey = stopHotKey
        }

        // Built only when there is somewhere to keep the console designations. A
        // build with no database has no admin rooms, so the pipeline runs without
        // the check rather than with a use case that can never match.
        let handleAdminCommand = adminStore.map { store in
            HandleAdminCommand(
                connection: kakao,
                sender: sender,
                policyStore: policyStore,
                adminRoomStore: store,
                personNotes: personNotes,
                actionLog: actionLog,
                // A !세팅 write only touches the store; the rooms screen holds its
                // own snapshot. Hand the changed room back to it so the list row
                // and the summary catch up without the full room-list reload. The
                // model is captured here on the main actor and held weakly so this
                // closure never keeps it alive.
                onRoomPolicyChanged: { [weak chatRooms = models.chatRooms] roomID in
                    await chatRooms?.applyExternalPolicyChange(roomID: roomID)
                }
            )
        }

        models.startReplyPipeline(
            DraftRepliesForChangedRooms(
                connection: kakao,
                policyStore: policyStore,
                settingsStore: settingsStore,
                actionLog: actionLog,
                generator: CodexReplyGenerator(model: model),
                sendStore: sendStore,
                photoSource: KatokPhotoExtractor(),
                linkSource: WebKitLinkReader(),
                summaryStore: summaryStore,
                burningStore: burningStore,
                personNotes: personNotes
            ),
            // Runs at the top of each room's turn, ahead of the pipeline's own
            // gates, so a command is honored even in a paused or answer-nobody
            // console. The account is resolved inside the use case, like the
            // pipeline resolves its own.
            adminCommand: handleAdminCommand.map { handler in
                { @Sendable roomID in await handler.handle(roomID: roomID) }
            }
        )
        // Rides the send queue's poll rather than the sync stream: the rooms this
        // one looks for are the ones the stream never reports, because they have
        // stopped changing.
        models.startConversationOpener(
            OpenConversationsInQuietRooms(
                connection: kakao,
                policyStore: policyStore,
                settingsStore: settingsStore,
                actionLog: actionLog,
                generator: CodexReplyGenerator(model: model),
                sendStore: sendStore,
                summaryStore: summaryStore
            )
        )
        // Rides the same poll for the same reason the opener does, and above all
        // because it must not ride the sync stream: a reply may never wait behind
        // a summary call.
        models.startSummaryRefresh(
            RefreshConversationSummaries(
                connection: kakao,
                policyStore: policyStore,
                settingsStore: settingsStore,
                summaryStore: summaryStore,
                writer: CodexSummaryWriter(model: model),
                personNotes: personNotes,
                actionLog: actionLog
            )
        )
        return models
    }

    /// The sender reads the acceptance at call time rather than capturing it, so
    /// revoking consent takes effect on the very next send.
    private static func messageSender(settingsStore: any AppSettingsStore) -> any MessageSender {
        AccessibilityFirstMessageSender(
            direct: AccessibilityMessageSender(),
            fallback: KatokMessageSender {
                (try? await settingsStore.sendUsePolicyAccepted()) ?? false
            }
        )
    }

    /// Every AI call asks which model to use, at the moment it calls, so a change
    /// in 설정 lands on the next reply instead of the next launch.
    ///
    /// A failed read falls back to 선택 안 함 rather than to a model of its own.
    /// That is the behaviour the app already had, and the alternative is a
    /// database hiccup taking every reply down with it.
    private static func aiModel(
        settingsStore: any AppSettingsStore
    ) -> @Sendable () async -> AIModelChoice {
        { (try? await settingsStore.aiModel()) ?? .codexDefault }
    }

    private static func policyStore() -> any RoomPolicyStore {
        database.map(RoomPolicyRepository.init(database:)) ?? UnavailableStore()
    }

    private static func settingsStore() -> any AppSettingsStore {
        database.map(AppSettingsRepository.init(database:)) ?? UnavailableStore()
    }

    private static func actionLog() -> any AgentActionLog {
        database.map(AgentActionRepository.init(database:)) ?? UnavailableStore()
    }

    private static func sendStore() -> any PendingSendStore {
        database.map(PendingSendRepository.init(database:)) ?? UnavailableSendStore()
    }

    private static func summaryStore() -> any ConversationSummaryStore {
        database.map(ConversationSummaryRepository.init(database:)) ?? UnavailableStore()
    }

    /// Nil without a database, and a room simply never burns. Everything else on
    /// the room screen degrades that way too — the settings are still readable,
    /// they just have nowhere to be remembered.
    private static func burningStore() -> (any BurningStateStore)? {
        database.map(BurningStateRepository.init(database:))
    }

    /// Nil without a database, and no room remembers anybody. Every room ships
    /// with 사람 기억 off anyway, so this degrades to what a fresh install does.
    private static func personNotes() -> (any PersonNoteStore)? {
        database.map(PersonNoteRepository.init(database:))
    }

    /// Nil without a database, and no room can be a console. Admin mode ships off
    /// for every room, so this degrades to what a fresh install does — nothing is
    /// designated and no command is honored.
    private static func adminRoomStore() -> (any AdminRoomStore)? {
        database.map(AdminRoomRepository.init(database:))
    }
}
