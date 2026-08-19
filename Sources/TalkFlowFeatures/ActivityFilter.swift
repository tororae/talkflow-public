import Foundation
import TalkFlowDomain

/// What the 활동 화면 currently shows of the record, and the rooms it offers to
/// narrow by.
///
/// Kept out of both the view and the model so the narrowing rules can be read
/// and tested on their own. With the 초안 화면 gone this table is the only way
/// to reach a draft, so a filter that drops one has to be a filter the user set
/// on purpose.
public struct ActivityFilter: Equatable, Sendable {
    /// The outcomes worth sorting by. `dismissed` is folded into 보류 rather than
    /// getting a box of its own: both mean nothing was sent and somebody meant it
    /// that way, and the distinction is who decided.
    ///
    /// 먼저 말 걸기 does get its own box, and not because there are more of them —
    /// there are far fewer. It is the only row on this screen that TalkFlow wrote
    /// with nobody having asked, and folding it into 초안 would make the one thing
    /// worth checking on findable only by reading every row. Both its outcomes go
    /// here, the written and the passed-over, so "무엇을 먼저 말했나" is one tick box
    /// rather than two.
    public enum Category: String, CaseIterable, Identifiable, Sendable {
        case drafted
        case opened
        case sent
        case held
        case failed

        public var id: Self { self }

        public var title: String {
            switch self {
            case .drafted: "초안"
            case .opened: "먼저 말 걸기"
            case .sent: "보냄"
            case .held: "보류"
            case .failed: "실패"
            }
        }

        public init(kind: AgentAction.Kind) {
            switch kind {
            case .drafted: self = .drafted
            case .opened: self = .opened
            // 관리자 명령 rows do not answer to these result boxes at all — they ride
            // their own 「관리자」 switch (`showsCommands`), which is why the row-level
            // `includes` peels them off first. This mapping is only a fallback that
            // check never reaches, kept so the switch stays exhaustive.
            case .sent, .commanded: self = .sent
            case .held, .dismissed: self = .held
            case .failed: self = .failed
            }
        }
    }

    /// Everything, until the user says otherwise. Opening the screen onto a
    /// narrowed table would hide work nobody has been told about yet.
    public var categories: Set<Category> = Set(Category.allCases)

    /// How far the message got, which is a different question from what the app
    /// decided. 보류 holds both 「규칙만 보고 멈춤」 and 「모델이 답했는데 안 보냄」 —
    /// 3,249 against 1,221 on one measured account — and the 결과 boxes cannot
    /// tell them apart, so the expensive third of the record hides inside the
    /// free two thirds.
    public var reaches: Set<ActionReach> = Set(ActionReach.allCases)

    /// The rooms to keep, or `nil` for all of them. `nil` rather than a list of
    /// every id there happens to be right now, so a room whose first message
    /// arrives later is not quietly excluded by a choice made before it existed.
    public var roomIDs: Set<String>?

    /// Whether 관리자 명령(콘솔) rows show. Off by default and on its own switch,
    /// because they are console operations rather than message outcomes: a runaway
    /// console once wrote sixty in a row, and neither a screenful of them by default
    /// nor 「전체 선택」 turning them on by surprise is what the operator wants. 전체
    /// 선택/해제 leave this untouched; only its own box moves it.
    public var showsCommands = false

    public init() {}

    public var isNarrowed: Bool {
        categories.count != Category.allCases.count
            || reaches.count != ActionReach.allCases.count
            || roomIDs != nil
    }

    /// Whether the filter can currently match anything at all. An axis emptied to
    /// nothing shows a blank table, and 전체 해제 is off once it already has.
    public var showsNothing: Bool {
        categories.isEmpty || reaches.isEmpty || roomIDs?.isEmpty == true
    }

    public var roomSummary: String {
        guard let roomIDs else { return "채팅방 전체" }
        return roomIDs.isEmpty ? "채팅방 없음" : "채팅방 \(roomIDs.count)개"
    }

    /// A row is kept when *any* of its events matches 결과, because the row shows
    /// several — a message that was drafted and then sent answers to both boxes,
    /// and dropping it from 초안 because it later succeeded would hide the drafts
    /// that worked from the box named after drafts.
    public func includes(_ row: ActivityRow) -> Bool {
        guard includesRoom(row.latest.chatRoomID) else { return false }
        // 관리자 명령 rows answer only to their own switch — not the 결과 or 단계 axes,
        // so 전체 선택/해제 never sweeps them and they stay out until asked for.
        if row.isCommand { return showsCommands }
        guard reaches.contains(row.reach) else { return false }
        return row.actions.contains { categories.contains(Category(kind: $0.kind)) }
    }

    public func includesRoom(_ id: String) -> Bool {
        roomIDs?.contains(id) ?? true
    }

    public func apply(to rows: [ActivityRow]) -> [ActivityRow] {
        rows.filter(includes)
    }

    public mutating func setCategory(_ category: Category, included: Bool) {
        if included {
            categories.insert(category)
        } else {
            categories.remove(category)
        }
    }

    public mutating func setReach(_ reach: ActionReach, included: Bool) {
        if included {
            reaches.insert(reach)
        } else {
            reaches.remove(reach)
        }
    }

    /// The 결과 and 단계 axes at once — but not the rooms, and not 관리자 명령. Each of
    /// those has its own control (the room popover, the 관리자 box), and sweeping them
    /// from here is what let this button silently undo a room filter somebody set on
    /// purpose.
    ///
    /// One pair of buttons rather than a pair per axis: ticking the result and stage
    /// boxes back on one at a time is the thing being fixed.
    public mutating func selectAll() {
        categories = Set(Category.allCases)
        reaches = Set(ActionReach.allCases)
    }

    /// Empties the 결과 and 단계 axes — again leaving the rooms and 관리자 명령 as they
    /// were. The message table goes blank, which is the point: it is how somebody
    /// picks two boxes out of eleven without unticking nine.
    public mutating func clearAll() {
        categories = []
        reaches = []
    }

    /// Whether 결과·단계 are both fully on, so 「전체 선택」 would change nothing.
    public var allResultAndStageOn: Bool {
        categories.count == Category.allCases.count && reaches.count == ActionReach.allCases.count
    }

    /// Whether 결과·단계 are both fully off, so 「전체 해제」 would change nothing.
    public var allResultAndStageOff: Bool {
        categories.isEmpty && reaches.isEmpty
    }

    public mutating func setShowsCommands(_ shown: Bool) {
        showsCommands = shown
    }

    /// Turning one room off while every room is shown has to write down the
    /// rest; ticking the last missing one back on returns to "all rooms" rather
    /// than freezing today's list into the filter.
    public mutating func setRoom(_ id: String, included: Bool, amongst rooms: [String]) {
        var next = roomIDs ?? Set(rooms)
        if included {
            next.insert(id)
        } else {
            next.remove(id)
        }
        roomIDs = next.isSuperset(of: rooms) ? nil : next
    }

    public mutating func selectAllRooms() {
        roomIDs = nil
    }

    /// Empties the room list so a couple of rooms can be picked out of many
    /// without unticking the rest one at a time.
    public mutating func clearRooms() {
        roomIDs = []
    }
}

/// A room the user can filter by, taken from the actions actually recorded so
/// the popover never lists a room with no history behind it.
public struct ActivityRoomOption: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let count: Int

    public static func options(from actions: [AgentAction]) -> [ActivityRoomOption] {
        var order: [String] = []
        var names: [String: String] = [:]
        var counts: [String: Int] = [:]

        for action in actions {
            if counts[action.chatRoomID] == nil {
                order.append(action.chatRoomID)
            }
            counts[action.chatRoomID, default: 0] += 1
            // The newest row wins the label: a room renamed since is listed
            // under the name the user last saw in KakaoTalk.
            if names[action.chatRoomID] == nil, !action.chatRoomName.isEmpty {
                names[action.chatRoomID] = action.chatRoomName
            }
        }

        return order
            .map { id in
                ActivityRoomOption(id: id, name: names[id] ?? id, count: counts[id] ?? 0)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
