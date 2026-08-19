import Foundation
import Observation
import TalkFlowApplication
import TalkFlowDomain

/// State for the 활동 화면: the whole record, the part of it the filters let
/// through, and the send/dismiss decisions that used to need a screen of their
/// own.
///
/// Drafts were split off into a second tab, which meant the one list that shows
/// what TalkFlow did could not act on any of it, and the tab holding the work
/// was the one nobody was looking at. They are the same list.
@MainActor
@Observable
public final class ActivityTimelineModel {
    /// How many events one page is. 「더 보기」 widens the window by this much and
    /// re-reads, so the whole record is reachable a page at a time rather than
    /// frozen at the most recent 200 events — which on a busy account was only the
    /// last few hours, everything older simply unreachable.
    public static let pageSize = 200
    /// The first page's size, kept under its old name for the callers and tests
    /// that still read it.
    public static let historyLimit = pageSize

    public private(set) var actions: [AgentAction] = []
    /// How many events the table currently asks for. Grows by a page each 「더 보기」;
    /// a reload re-reads the whole span, so new activity at the top and the older
    /// activity below it arrive together instead of one overwriting the other.
    private var loadedLimit = pageSize
    /// What the last `recent` returned. Equal to `loadedLimit` means the window
    /// filled and there is very likely more behind it; fewer means the bottom of
    /// the record is already on screen. Read instead of a COUNT so 「더 보기」 costs
    /// no extra query.
    private var loadedEventCount = 0
    public private(set) var isLoadingMore = false
    /// Which of `actions` are still waiting on a person. Drafts resolve by
    /// being sent or dismissed, never by failing, so this shrinks only when a
    /// decision was made.
    public private(set) var pendingDraftIDs: Set<Int64> = []
    public private(set) var failure: String?
    public private(set) var actionFailure: String?
    public private(set) var usePolicyAccepted = false
    public private(set) var sendingID: Int64?
    public private(set) var selectedActionID: Int64?
    /// The body being edited for the selected draft. Replaced only by a
    /// deliberate selection — see `reload()`.
    public var editedText = ""
    public var filter = ActivityFilter()

    private let log: any AgentActionLog
    private let reviewDrafts: ReviewDrafts

    public init(log: any AgentActionLog, reviewDrafts: ReviewDrafts) {
        self.log = log
        self.reviewDrafts = reviewDrafts
    }

    /// The table's rows: one per message, filtered.
    ///
    /// Grouped before filtering, not after. 어디까지 갔나 is read off the stages of
    /// every event about a message merged together — the 전송 row carries no 판단
    /// stamp and the 초안 row carries no 전송 — so a filter applied to loose rows
    /// would be asking each half about the whole.
    public var visibleRows: [ActivityRow] {
        filter.apply(to: ActivityRow.rows(from: actions))
    }

    public var roomOptions: [ActivityRoomOption] {
        ActivityRoomOption.options(from: actions)
    }

    public var selectedAction: AgentAction? {
        actions.first { $0.id == selectedActionID }
    }

    /// Every stage of the selected reply, gathered from all the rows that make it
    /// up rather than only the one that was clicked.
    ///
    /// One reply is written down more than once — the draft when the model
    /// answers, the delivery when the queue lets it out, a failure in between —
    /// because each of those is a separate thing the app did and the timeline
    /// shows all of them. But "왜 이 답장이 늦었나" is one question spanning all of
    /// them, and answering it from whichever row happened to be selected would
    /// show the model's seconds or the queue's minutes and never both.
    ///
    /// Rows already in hand, so this costs a pass over the loaded history and no
    /// query. Grouped by `ActivityRow`, which is the same gathering the table does
    /// — written twice, the two would eventually disagree about which events belong
    /// to one message, and the pane would then show a duration for a different set
    /// of events than the line that was clicked.
    public func timeline(for action: AgentAction) -> ActionTimeline {
        ActivityRow.rows(from: actions)
            .first { $0.actions.contains { $0.id == action.id } }?
            .timeline
            ?? action.timeline
    }

    /// Nil when the selected row has no durations worth a section — an old row,
    /// or a dismissal, which happened the instant it was asked for.
    ///
    /// Internal like the section it returns: this is the shape one screen draws,
    /// not something another module has business reading.
    var selectedTimelineSection: ActionTimelineSection? {
        guard let selectedAction else { return nil }
        return ActionTimelineSection.of(timeline(for: selectedAction))
    }

    /// The run — or the single trigger line — that a record answered, gathered from
    /// the event in its group that kept it rather than the one that was clicked. A
    /// 전송 record keeps neither the run nor the original message, so read off
    /// itself it shows nothing of what it replied to; the draft in the same group
    /// is where that lives. Grouped by `ActivityRow`, the same gathering the table
    /// and `timeline(for:)` already do.
    func answeredSection(for action: AgentAction, voice: AnsweredRunSection.Voice) -> AnsweredRunSection? {
        let source = ActivityRow.rows(from: actions)
            .first { $0.actions.contains { $0.id == action.id } }?
            .answeredContextAction ?? action
        return AnsweredRunSection.of(source, voice: voice)
    }

    /// What triggered the reply behind a record — mention, direct message, or a
    /// group the account joined on its own — gathered from its group, since a 전송
    /// record does not keep it and the draft in the same group does.
    func replyTrigger(for action: AgentAction) -> ReplyTrigger? {
        ActivityRow.rows(from: actions)
            .first { $0.actions.contains { $0.id == action.id } }?
            .replyTrigger ?? action.replyMode
    }

    public var pendingDraftCount: Int {
        pendingDraftIDs.count
    }

    public func isPending(_ action: AgentAction) -> Bool {
        pendingDraftIDs.contains(action.id)
    }

    public var isSelectedDraftPending: Bool {
        guard let selectedAction else { return false }
        return isPending(selectedAction)
    }

    public var isEdited: Bool {
        guard let selectedAction else { return false }
        return editedText != (selectedAction.replyText ?? "")
    }

    public var summary: String {
        if let failure { return failure }
        guard !actions.isEmpty else { return "아직 기록된 활동이 없습니다." }
        // Both numbers count messages, not recorded events, because that is what
        // the table now draws — saying 「표시 40건 / 전체 7,100건」 next to forty
        // lines gathered from ninety events would have the two disagree.
        // 관리자 명령 rows are off by default and on their own switch, so the 「전체」
        // count follows the same rule — otherwise a hidden runaway console would
        // inflate 전체 by rows the table never draws.
        let rows = ActivityRow.rows(from: actions).filter { !$0.isCommand || filter.showsCommands }.count
        // 「전체」 is only honest once the whole record is loaded. While 「더 보기」 can
        // still bring older rows, this counts what is on screen, not what exists —
        // calling that 전체 with thousands still unloaded is the thing that read as
        // a filter quietly dropping history.
        let scope = canLoadMore ? "최근" : "전체"
        if filter.isNarrowed {
            return "표시 \(visibleRows.count)건 / \(scope) \(rows)건"
        }
        return canLoadMore ? "\(scope) \(rows)건 · 더 있음" : "전체 \(rows)건"
    }

    /// Nil when there is nothing waiting, so the screen can leave the line out
    /// entirely rather than say "0건" and read like a status that never changes.
    public var pendingSummary: String? {
        pendingDraftCount > 0 ? "검토 대기 \(pendingDraftCount)건" : nil
    }

    /// Reloaded on every KakaoTalk sync, which is why it touches neither the
    /// selection nor `editedText`: a refresh landing mid-sentence used to throw
    /// away whatever the user was typing into the draft.
    public func reload() async {
        do {
            let recent = try await log.recent(limit: loadedLimit)
            loadedEventCount = recent.count
            let pending = try await reviewDrafts.pending()
            pendingDraftIDs = Set(pending.map(\.id))
            actions = Self.merge(recent: recent, pending: pending)
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
        usePolicyAccepted = await reviewDrafts.usePolicyAccepted()
    }

    /// Whether older history than what is loaded very likely exists. Read off the
    /// last fetch having filled its window rather than a total: a full page means
    /// the limit ended the list, not the record.
    public var canLoadMore: Bool { loadedEventCount >= loadedLimit }

    /// Widens the window by one page and re-reads. The selection and the draft
    /// being edited survive it — `reload` leaves both alone — so pulling in older
    /// rows never disturbs a review in progress.
    public func loadMore() async {
        guard canLoadMore, !isLoadingMore else { return }
        isLoadingMore = true
        loadedLimit += Self.pageSize
        await reload()
        isLoadingMore = false
    }

    public func select(id: Int64?) {
        guard id != selectedActionID else { return }
        selectedActionID = id
        editedText = actions.first { $0.id == id }?.replyText ?? ""
        actionFailure = nil
    }

    public func setRoom(_ id: String, included: Bool) {
        filter.setRoom(id, included: included, amongst: roomOptions.map(\.id))
    }

    public func sendSelected() async {
        guard let draft = selectedAction, isPending(draft) else { return }
        actionFailure = nil
        sendingID = draft.id
        do {
            try await reviewDrafts.send(draft, text: isEdited ? editedText : nil)
        } catch {
            actionFailure = error.localizedDescription
        }
        sendingID = nil
        await finishReview()
    }

    public func dismissSelected() async {
        guard let draft = selectedAction, isPending(draft) else { return }
        actionFailure = nil
        do {
            try await reviewDrafts.dismiss(draft)
        } catch {
            actionFailure = error.localizedDescription
        }
        await finishReview()
    }

    /// After a decision the next waiting draft is selected, so a backlog can be
    /// worked through without hunting for the next row among everything else
    /// the table holds. Only ever here: the user asked for this one.
    private func finishReview() async {
        await reload()
        guard actionFailure == nil,
              let next = visibleRows.lazy.flatMap(\.actions).first(where: { isPending($0) })
        else {
            return
        }
        select(id: next.id)
    }

    /// A draft older than the history window still has to be reachable now that
    /// this table is the only place it can be sent from.
    private static func merge(recent: [AgentAction], pending: [AgentAction]) -> [AgentAction] {
        let known = Set(recent.map(\.id))
        let missing = pending.filter { !known.contains($0.id) }
        guard !missing.isEmpty else { return recent }
        return (recent + missing).sorted { ($0.createdAt, $0.id) > ($1.createdAt, $1.id) }
    }
}
