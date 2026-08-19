/// Persistence ports for everything the user configures.
///
/// Policies are keyed by `(account fingerprint, chat room id)` so that renaming
/// a room, or signing into a different KakaoTalk account, never silently applies
/// somebody else's rules.
public protocol RoomPolicyStore: Sendable {
    /// Stored policy for the room, or the default one when the user has not
    /// configured it yet. Never returns nil so callers cannot forget the default.
    func policy(for room: ChatRoom, accountFingerprint: String) async throws -> RoomPolicy
    func policies(accountFingerprint: String) async throws -> [String: RoomPolicy]
    func save(_ policy: RoomPolicy) async throws

    /// Records the display names KakaoTalk currently reports, for screens and
    /// logs that need a name after a room disappears from the archive.
    func rememberRooms(_ rooms: [ChatRoom], accountFingerprint: String) async throws

    /// Rooms the user asked to stop seeing.
    ///
    /// Hidden rather than deleted, because there is nothing to delete: the room
    /// list is derived from the archive, and a room is in it because a message
    /// once arrived. Removing the row would bring the room back on the next load
    /// with its settings gone — a delete that loses the configuration and not the
    /// room is the worst of both.
    func hiddenRoomIDs(accountFingerprint: String) async throws -> Set<String>
    func setRoomHidden(_ hidden: Bool, chatRoomID: String, accountFingerprint: String) async throws

    /// Whether any room at all has 먼저 말 걸기 switched on.
    ///
    /// Asked first by the sweep that looks for quiet rooms, because that sweep
    /// runs every few seconds and the answer is no for everybody who has not gone
    /// looking for the setting. Behind it are a process launch to verify the
    /// account and a read of every room's messages, and neither is worth spending
    /// on a feature nobody turned on.
    ///
    /// Deliberately not scoped to an account: it stands in front of the account
    /// check rather than replacing it, and a yes from some other account's room
    /// only costs the check that follows.
    func anyRoomOpensConversations() async throws -> Bool
}

public protocol AppSettingsStore: Sendable {
    func responseStyle() async throws -> ResponseStyle
    func save(_ style: ResponseStyle) async throws

    /// 답변 조건, in force in every room that has not written its own. Read and
    /// written apart from the style because a room overrides the two separately,
    /// and because one is about what an answer says and the other about whether
    /// there is one.
    func answeringCondition() async throws -> AnsweringCondition
    func save(_ condition: AnsweringCondition) async throws

    /// The global on/off switch, which survives relaunches so a paused app stays
    /// paused rather than quietly resuming.
    func globalResponsesEnabled() async throws -> Bool
    func setGlobalResponsesEnabled(_ enabled: Bool) async throws

    func launchesAtLogin() async throws -> Bool
    func setLaunchesAtLogin(_ enabled: Bool) async throws

    /// Whether the user accepted the connector's acceptable-use policy and
    /// disclaimer. Nothing is ever sent before this is true, and only the user
    /// can set it.
    func sendUsePolicyAccepted() async throws -> Bool
    func setSendUsePolicyAccepted(_ accepted: Bool) async throws

    /// Whether TalkFlow may wake the display to deliver a queued message.
    /// Without it, nothing is ever sent while the screen is off, because the
    /// lock screen holds the front and UI automation has nothing to type into.
    func wakesDisplayToSend() async throws -> Bool
    func setWakesDisplayToSend(_ enabled: Bool) async throws

    /// Which model every AI call asks for.
    ///
    /// Never nil, for the reason a room's policy never is: `codexDefault` is a
    /// real answer — leave the flag off and let Codex CLI's own config decide —
    /// and an Optional would let a caller treat "not chosen" as "not loaded" and
    /// go looking for a fallback of its own.
    func aiModel() async throws -> AIModelChoice
    func setAIModel(_ choice: AIModelChoice) async throws
}
