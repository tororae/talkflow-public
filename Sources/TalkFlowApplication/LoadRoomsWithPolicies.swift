import TalkFlowDomain

public struct ChatRoomPolicy: Identifiable, Equatable, Sendable {
    public let room: ChatRoom
    public var policy: RoomPolicy
    /// Whether KakaoTalk is still showing this room in its own chat list.
    ///
    /// False does not mean the account left. KakaoTalk exposes only the rows it
    /// has rendered, so a room below the fold reads exactly like one that was
    /// left — which is why this marks a room and never removes one.
    ///
    /// Nil when the list could not be read at all. Nothing is known then, and a
    /// screen that drew 「목록에 없음」 on every room because KakaoTalk was closed
    /// would be worse than one that drew nothing.
    public let isListedByKakaoTalk: Bool?
    /// Whether the user asked to stop seeing this room.
    ///
    /// Marked rather than filtered out here, because whether a hidden room is on
    /// screen is a question about the screen. The use case's job is to say what
    /// is true of every room; leaving one out would also leave the user no way
    /// back to it.
    public let isHidden: Bool
    /// Whether this room's chat window is open right now.
    ///
    /// The difference between a reply that goes out in a second without moving
    /// anything and one that does not go out at all: automatic delivery refuses
    /// to open a closed room, because opening one takes the screen and can type
    /// the room's name into somebody's conversation when it goes wrong.
    ///
    /// Nil when nothing could be read. Only the active Space is visible, so a
    /// window on another desktop reads as closed.
    public let hasOpenWindow: Bool?

    public var id: String { room.id }

    /// The state worth acting on: set to answer by itself, and unable to.
    public var isBlockedByClosedWindow: Bool {
        policy.deliveryMode.deliversAutomatically
            && policy.responseMode != .off
            && policy.responseMode != .detectOnly
            && hasOpenWindow == false
    }

    public init(
        room: ChatRoom,
        policy: RoomPolicy,
        isListedByKakaoTalk: Bool? = nil,
        isHidden: Bool = false,
        hasOpenWindow: Bool? = nil
    ) {
        self.room = room
        self.policy = policy
        self.isListedByKakaoTalk = isListedByKakaoTalk
        self.isHidden = isHidden
        self.hasOpenWindow = hasOpenWindow
    }
}

public struct RoomPolicyBoard: Equatable, Sendable {
    public let accountFingerprint: String
    /// Carried on the board because the rooms screen has to show what every
    /// room answers to, and the name is only knowable where the account is
    /// verified. Read once per load instead of once per room.
    public let accountNickname: String?
    /// What 설정 currently holds. Carried so a room can show what it is following
    /// — and start from it, rather than from the app's defaults, the moment
    /// somebody switches an override on.
    public let globalStyle: ResponseStyle
    public let globalCondition: AnsweringCondition
    public let entries: [ChatRoomPolicy]

    public init(
        accountFingerprint: String,
        accountNickname: String? = nil,
        globalStyle: ResponseStyle = ResponseStyle(),
        globalCondition: AnsweringCondition = .empty,
        entries: [ChatRoomPolicy]
    ) {
        self.accountFingerprint = accountFingerprint
        self.accountNickname = accountNickname
        self.globalStyle = globalStyle
        self.globalCondition = globalCondition
        self.entries = entries
    }

    /// The keywords registered in 설정, so a room can show its own words next to
    /// the ones it inherits. Read off the style because that is where they live;
    /// a second copy would be a second thing to keep in step.
    public var globalKeywords: [String] { globalStyle.responseKeywords }

    public func callSigns(for entry: ChatRoomPolicy) -> CallSigns {
        CallSigns(nickname: accountNickname, globalKeywords: globalKeywords, policy: entry.policy)
    }
}

public enum RoomPolicyLoadError: Error {
    case accountNotVerified(reason: String)
}

/// Pairs every chat room with the policy that governs it.
///
/// The account fingerprint is resolved here rather than passed in, so no screen
/// can ask for one account's rooms while holding another account's policies.
public struct LoadRoomsWithPolicies: Sendable {
    private let connection: any KakaoConnection
    private let policyStore: any RoomPolicyStore
    private let settingsStore: any AppSettingsStore

    public init(
        connection: any KakaoConnection,
        policyStore: any RoomPolicyStore,
        settingsStore: any AppSettingsStore
    ) {
        self.connection = connection
        self.policyStore = policyStore
        self.settingsStore = settingsStore
    }

    public func callAsFunction() async throws -> RoomPolicyBoard {
        let account: AccountProfile
        switch await connection.status() {
        case let .connected(profile):
            account = profile
        case let .unavailable(reason):
            throw RoomPolicyLoadError.accountNotVerified(reason: reason)
        case .disconnected:
            throw RoomPolicyLoadError.accountNotVerified(reason: "카카오톡에 연결되어 있지 않습니다.")
        }

        let fingerprint = account.fingerprint
        let rooms = try await connection.chatRooms()
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        try await policyStore.rememberRooms(rooms, accountFingerprint: fingerprint)

        let stored = try await policyStore.policies(accountFingerprint: fingerprint)
        // Read once for the whole board. It is one process launch, and asking it
        // per room would be one per room for an answer that does not vary.
        let hidden = (try? await policyStore.hiddenRoomIDs(accountFingerprint: fingerprint)) ?? []

        let entries = rooms.map { room in
            ChatRoomPolicy(
                room: room,
                policy: stored[room.id] ?? .makeDefault(accountFingerprint: fingerprint, room: room),
                isHidden: hidden.contains(room.id)
            )
        }

        return RoomPolicyBoard(
            accountFingerprint: fingerprint,
            accountNickname: account.nickname,
            globalStyle: try await settingsStore.responseStyle(),
            globalCondition: try await settingsStore.answeringCondition(),
            entries: entries
        )
    }
}

public struct SaveRoomPolicy: Sendable {
    private let policyStore: any RoomPolicyStore

    public init(policyStore: any RoomPolicyStore) {
        self.policyStore = policyStore
    }

    public func callAsFunction(_ policy: RoomPolicy) async throws {
        try await policyStore.save(policy)
    }
}

/// One room's stored policy, read on its own.
///
/// Its own use case rather than a whole `LoadRoomsWithPolicies` because the reason
/// it exists is to be cheap: refreshing a single room after an outside change (an
/// admin `!세팅` write) is one indexed read, not the room-list fetch that drives
/// KakaoTalk. Returns the default when the room has never been configured, the same
/// promise the store makes.
public struct ReadRoomPolicy: Sendable {
    private let policyStore: any RoomPolicyStore

    public init(policyStore: any RoomPolicyStore) {
        self.policyStore = policyStore
    }

    public func callAsFunction(room: ChatRoom, accountFingerprint: String) async throws -> RoomPolicy {
        try await policyStore.policy(for: room, accountFingerprint: accountFingerprint)
    }
}
