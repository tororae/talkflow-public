import Observation
import TalkFlowApplication
import TalkFlowDomain

@MainActor
@Observable
public final class ChatRoomListModel {
    public enum State: Equatable {
        case idle
        case loading
        case loaded(RoomPolicyBoard)
        case failed(String)
    }

    public internal(set) var state: State = .idle
    public var searchText = ""
    public var selectedRoomID: String?
    public var showsHiddenRooms = false
    /// What KakaoTalk was last seen showing. Arrives after the rooms do, because
    /// reading it drives KakaoTalk's interface and the list must not wait on that
    /// — see `InspectRoomPresence`.
    var presence: InspectRoomPresence.Report = .unknown
    /// Nil while the answer is unknown, which the room screen shows as "확인 중"
    /// rather than as "nobody called".
    public internal(set) var recentCalls: RecentCallReport?
    /// Which room `recentCalls` and `judgementCycle` were read for. The read is
    /// slow, and opening another room mid-read must not land the first room's
    /// answer in the second — the same guard RoomSummaryModel keeps. Tracked here
    /// rather than off `selectedRoomID` so the load races the room being
    /// inspected, not whatever the user has since clicked.
    var inspectingRoomID: String?
    /// Nil for a room that judges every message, or one that has never been
    /// asked anything — in both cases there is no wait to describe.
    public internal(set) var judgementCycle: JudgementCycle?
    public internal(set) var keywordIssue: String?
    /// Set when a room's 답변 조건 was refused, so the field keeps what was typed
    /// instead of the text disappearing under the cursor.
    public internal(set) var conditionIssue: String?

    /// Edits made but not yet saved. See `RoomPolicyDrafts`.
    private var drafts = RoomPolicyDrafts()
    public private(set) var saveStatus: RoomSaveStatus = .idle

    /// Rooms whose stored policy changed from outside this screen — an admin `!세팅`
    /// write — while the screen was holding an unsaved edit for them. The list and
    /// the summary always read the fresh value; this exists only so the editor can
    /// warn that saving its draft would overwrite what just arrived.
    public private(set) var externallyChangedRoomIDs: Set<String> = []

    public enum RoomSaveStatus: Equatable {
        case idle
        case saving
        case saved
        case failed(String)
    }

    let loadRooms: LoadRoomsWithPolicies
    let saveRoomPolicy: SaveRoomPolicy
    private let readRoomPolicy: ReadRoomPolicy
    let hideRoom: HideChatRoom
    let inspectCalls: InspectRecentCalls
    let inspectPresence: InspectRoomPresence
    let inspectCycle: InspectJudgementCycle

    public init(
        loadRooms: LoadRoomsWithPolicies,
        saveRoomPolicy: SaveRoomPolicy,
        readRoomPolicy: ReadRoomPolicy,
        hideRoom: HideChatRoom,
        inspectCalls: InspectRecentCalls,
        inspectPresence: InspectRoomPresence,
        inspectCycle: InspectJudgementCycle
    ) {
        self.loadRooms = loadRooms
        self.saveRoomPolicy = saveRoomPolicy
        self.readRoomPolicy = readRoomPolicy
        self.hideRoom = hideRoom
        self.inspectCalls = inspectCalls
        self.inspectPresence = inspectPresence
        self.inspectCycle = inspectCycle
    }

    // MARK: - 저장하지 않은 편집

    /// What the screen should show for a room: its pending edit if it has one,
    /// otherwise what is on disk.
    public func editedPolicy(for entry: ChatRoomPolicy) -> RoomPolicy {
        drafts.draft(for: entry)
    }

    /// Records a change without writing it. The only way the screen edits a room.
    public func edit(_ entry: ChatRoomPolicy, _ change: (inout RoomPolicy) -> Void) {
        drafts.edit(entry, change)
        saveStatus = .idle
    }

    public func hasUnsavedChanges(_ entry: ChatRoomPolicy) -> Bool {
        drafts.has(entry)
    }

    /// Which rooms are holding edits, so the list can mark them. A room whose
    /// pending change is out of sight is a change the user will forget they made.
    public var unsavedRoomIDs: Set<String> {
        drafts.editedIDs
    }

    public func saveEdits(for entry: ChatRoomPolicy) async {
        guard drafts.has(entry) else { return }
        saveStatus = .saving
        await update(drafts.draft(for: entry))
        if case let .failed(reason) = state {
            saveStatus = .failed(reason)
            return
        }
        drafts.discard(entry)
        // Saving the draft is a choice to keep it over any outside change, so the
        // conflict it warned about is now resolved either way.
        externallyChangedRoomIDs.remove(entry.id)
        saveStatus = .saved
    }

    /// Back to what is on disk, in one step. The counterpart to 저장 and the
    /// reason a person can try a setting without committing to it.
    public func revertEdits(for entry: ChatRoomPolicy) {
        drafts.discard(entry)
        externallyChangedRoomIDs.remove(entry.id)
        saveStatus = .idle
    }

    // MARK: - 외부(관리자 명령)에서 바뀐 정책

    /// Re-reads one room's stored policy and patches just that entry into the
    /// board, so the list row and the "응답 켠 방 N개" count catch up without the
    /// room-list fetch a full `reload` runs — that fetch drives KakaoTalk, this is
    /// one indexed read. Called when an admin `!세팅` command wrote this room.
    ///
    /// The board — and so the list and the summary — always takes the fresh value.
    /// The editor is the exception: it shows a pending draft when one exists, so a
    /// room being edited keeps its unsaved value and is flagged instead, because
    /// 저장 there would still write the draft over what just arrived.
    public func applyExternalPolicyChange(roomID: String) async {
        guard case let .loaded(board) = state,
              let entry = board.entries.first(where: { $0.room.id == roomID })
        else {
            return
        }
        guard let fresh = try? await readRoomPolicy(room: entry.room, accountFingerprint: board.accountFingerprint),
              fresh != entry.policy
        else {
            // Nothing to do when the store already matches what the board shows —
            // this room's own 저장 comes back around as this same call.
            return
        }

        let entries = board.entries.map { current in
            current.room.id == roomID
                ? ChatRoomPolicy(room: current.room, policy: fresh, isHidden: current.isHidden)
                : current
        }
        state = .loaded(
            RoomPolicyBoard(
                accountFingerprint: board.accountFingerprint,
                accountNickname: board.accountNickname,
                globalStyle: board.globalStyle,
                globalCondition: board.globalCondition,
                entries: entries
            )
        )
        // Only the editor can lose work here: the list read the fresh value above.
        if drafts.has(entry) { externallyChangedRoomIDs.insert(roomID) }
        // As in `update`: if this is the room on screen, the 다음 판단 footnote was
        // derived from the old interval and would otherwise keep describing it.
        if roomID == selectedRoomID,
           let patched = entries.first(where: { $0.room.id == roomID }) {
            await refreshJudgementCycle(for: patched)
        }
    }

    /// Whether this room's stored settings changed under an unsaved edit, so the
    /// editor can say so rather than let 저장 quietly overwrite what arrived.
    public func wasExternallyChanged(_ entry: ChatRoomPolicy) -> Bool {
        externallyChangedRoomIDs.contains(entry.id)
    }

    /// Drop the unsaved edit and take the value that arrived from outside — the
    /// editor's way out of the warning that keeps the incoming change.
    public func adoptExternalChange(for entry: ChatRoomPolicy) {
        drafts.discard(entry)
        externallyChangedRoomIDs.remove(entry.id)
        saveStatus = .idle
    }

    /// This room's own 답변 조건, as typed. Nil clears the override and puts the
    /// room back on the one in 설정.
    ///
    /// Takes the raw text rather than a built condition, because the built one is
    /// already inside the limit — the value type trims to it — and a check made
    /// after that would never fire. Refuses rather than shortens: a field that
    /// rewrites itself while somebody is typing is what made the keyword box
    /// impossible to use, so an overlong condition stays on screen with the reason
    /// beside it and is simply not saved.
    public func setAnsweringCondition(_ text: String?, for entry: ChatRoomPolicy) {
        if let text, AnsweringCondition.exceedsLimit(text) {
            conditionIssue = "\(AnsweringCondition.characterLimit)자까지 적을 수 있습니다."
            return
        }

        conditionIssue = nil
        edit(entry) { $0.answeringConditionOverride = text.map(AnsweringCondition.init) }
    }

    /// Held with everything else the room has pending, and written by 저장.
    /// Returns false when the word was refused, so the field keeps what was typed
    /// instead of swallowing it.
    ///
    /// It used to save the instant a word was accepted, which made the room
    /// screen follow two rules at once — some controls immediate, some not — and
    /// left 취소 unable to take back a keyword the user had just tried.
    @discardableResult
    public func addKeyword(_ text: String, to entry: ChatRoomPolicy) -> Bool {
        let keyword = CallSigns.normalized(text)
        guard !keyword.isEmpty else {
            keywordIssue = "키워드를 입력해 주세요."
            return false
        }
        // Checked against everything the room already answers to, not just its
        // own list: a word the name or a global keyword already covers would sit
        // in the list looking like it does something.
        let signs = callSigns(for: entry)
        if let existing = signs.all.first(where: { $0.caseInsensitiveCompare(keyword) == .orderedSame }) {
            keywordIssue = existing == signs.nickname
                ? "이미 내 이름으로 반응합니다."
                : "이미 등록된 키워드입니다."
            return false
        }

        keywordIssue = nil
        edit(entry) { $0.responseKeywords.append(keyword) }
        return true
    }

    public func removeKeyword(_ keyword: String, from entry: ChatRoomPolicy) {
        guard editedPolicy(for: entry).responseKeywords.contains(keyword) else { return }
        keywordIssue = nil
        edit(entry) { $0.responseKeywords.removeAll { $0 == keyword } }
    }
}
